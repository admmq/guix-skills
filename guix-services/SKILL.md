---
name: guix-services
description: Write new Guix System or Guix Home service types, covering configuration records (define-record-type* or define-configuration), Shepherd services (provision, requirement, forkexec constructors, logging, respawn), service extensions (shepherd, accounts, activation, profile, etc, udev), default values, and testing with herd. Use when a daemon or background job has no existing Guix service, when packaging software that needs a privileged helper daemon, or when turning a hand-run command into a declarative service.
---

# Writing Guix service types

Related skills: `guix-system-configuration` (using services), `guix-home` (user services), `guix-channels` (where to put them).

First check that the service doesn't already exist: `guix system search <word>`, `guix home search <word>`.

## Anatomy (system service running a daemon)

```scheme
(define-module (my-channel services foo)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu system shadow)          ; user-account, user-group
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:use-module (my-channel packages foo)
  #:export (foo-configuration
            foo-configuration?
            foo-service-type))

(define-record-type* <foo-configuration>
  foo-configuration make-foo-configuration
  foo-configuration?
  (package   foo-configuration-package   (default foo))
  (port      foo-configuration-port      (default 8080))
  (extra-args foo-configuration-extra-args (default '())))

(define (foo-shepherd-services config)
  (list
   (shepherd-service
    (documentation "Run the foo daemon.")
    (provision '(foo))
    (requirement '(networking user-processes))
    (respawn? #t)
    (start #~(make-forkexec-constructor
              (list #$(file-append (foo-configuration-package config) "/bin/food")
                    "--port" #$(number->string (foo-configuration-port config))
                    #$@(foo-configuration-extra-args config))
              #:user "foo" #:group "foo"            ; omit to run as root
              #:log-file "/var/log/foo.log"))
    (stop #~(make-kill-destructor)))))

(define (foo-accounts config)
  (list (user-group (name "foo") (system? #t))
        (user-account (name "foo") (group "foo") (system? #t)
                      (comment "foo daemon user")
                      (home-directory "/var/empty")
                      (shell (file-append shadow "/sbin/nologin")))))

(define (foo-activation config)
  #~(begin (use-modules (guix build utils))
           (mkdir-p "/var/lib/foo")))

(define foo-service-type
  (service-type
   (name 'foo)
   (extensions
    (list (service-extension shepherd-root-service-type foo-shepherd-services)
          (service-extension account-service-type foo-accounts)
          (service-extension activation-service-type foo-activation)
          ;; also put the client on everyone's PATH:
          (service-extension profile-service-type
                             (compose list foo-configuration-package))))
   (default-value (foo-configuration))
   (description "Run the foo daemon, which ….")))
```

Usage: `(service foo-service-type)`, or `(service foo-service-type (foo-configuration (port 9090)))`.

## Notes

- **Privileged helper plus GUI pattern** (VPN clients and similar): the service runs the helper daemon as root, and the GUI comes from the package installed in `packages` or a user profile. Say this in the service `description`. If the GUI isn't on `PATH`, users think the service is broken.
- `requirement`: use `'(networking)` for network daemons, `'(user-processes)` for anything after early boot, and `'(dbus-system)` or `'(elogind)` when the daemon needs those. Name exactly what the daemon needs. Too much delays boot, and too little makes it race.
- `#$@` splices a list of strings into the command. `#$(file-append pkg "/bin/x")` gives the store path of a program.
- Environment: `#:environment-variables (list "HOME=/var/lib/foo" …)`. Without it, the daemon inherits an almost empty environment.
- Generated config files: `(mixed-text-file "foo.conf" "port=" (number->string port) "\n")` or `plain-file`, passed on the command line. Or extend `etc-service-type` with `(list `("foo.conf" ,file))` to create `/etc/foo.conf`.
- Hardening: `least-authority-wrapper` from `(guix least-authority)` runs the daemon in a namespace with only the mappings you list.
- `define-configuration` from `(gnu services configuration)` is the documented alternative for services with many options. It generates documentation and serializers. A small `define-record-type*` is fine for a few fields.
- Extensible services: give your service-type `compose` and `extend` so others can `simple-service` into it.
- Other common extension targets: `udev-service-type` (rules packages), `privileged-program-service-type` (setuid), `mcron-service-type` (cron jobs), `dbus-root-service-type`, `polkit-service-type`, `pam-root-service-type`.

## Home (user) services

The same idea, with home targets:

```scheme
(simple-service 'foo-user-daemon home-shepherd-service-type
  (list (shepherd-service
         (provision '(foo-user))
         (start #~(make-forkexec-constructor
                   (list #$(file-append foo "/bin/foo") "--user")
                   #:log-file (string-append (getenv "XDG_STATE_HOME") "/log/foo.log")))
         (stop #~(make-kill-destructor)))))
```
Use `home-shepherd-service-type`, `home-files-service-type`, `home-xdg-configuration-files-service-type`, `home-environment-variables-service-type` and `home-profile-service-type`.

## Test

```sh
guix system build -L <channel> config.scm        # evaluates the service + config
guix system vm -L <channel> config.scm           # boot it in QEMU, check `herd status foo`
sudo herd status foo        # after reconfigure: running? last exit status?
sudo herd restart foo
sudo tail /var/log/foo.log /var/log/messages
```
A service that is "stopped" right after start with `respawn? #t` is usually crash-looping. Read its log before changing anything else.
