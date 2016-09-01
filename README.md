# SmartEntry

## overview

## feature

* file template
* file mode fixing
* volume initializing
* separate build script

## requirement

smartentry.sh only needs the following binary:

- bash
- busybox (cp, mv, stat, cat, tar, touch, mkdir, xargs, grep, sed, awk, find, read, md5sum)

The following image is tested:

- debian
- ubuntu
- CentOS
- fedora
- alpine

## base image

You can just use `FROM smartentry/<image>:<tag>` in your `Dockerfile`. 

They are built by DockerHub automatically, the source is in [the repository](https://github.com/gaoyifan/smartentry-images).

### image

The following images is provided:

* [debian](https://hub.docker.com/r/smartentry/debian/)
* [ubuntu](https://hub.docker.com/r/smartentry/ubuntu/)
* [CentOS](https://hub.docker.com/r/smartentry/centos/)
* [fedora](https://hub.docker.com/r/smartentry/fedora/)
* [alpine](https://hub.docker.com/r/smartentry/alpine/)

### tag

Tags is made up of original version and smartentry version: `<original_version>-<smartentry_version>`. 

For example: `smartentry/debian:8-beta` means  it is a debian 8 image with smartentry beta. You can use latest smartentry by omit "smartentry version", like `smartentry/debian:8`. It means debian 8 with the latest smartentry. You can also omit original version, like `smartentry/debian`. It means debian latest version with latest smartentry.

But it is highly recommended to use a complete tag to keep your building doing as expect in the future.

## tutorial

in progress...

## environment variables list

### DEBUG (default=*false*) 

smartentry debug mode.

### ENABLE_KEEP_USER_MODIFICATION (default=*true*)

Enable or disable ability for keeping user's file modification. The option only affect the files which appear in `$ROOTFS_DIR`.

If set to `true`, smartentry will not override the file that is different from original one, even if `$ENABLE_ROOTFS` is `true`.

If `$ENABLE_ROOTFS` is `false` , `$ENABLE_KEEP_USER_MODIFICATION` will be ignored.

### ENABLE_CHMOD_AUTO_FIX (default=*true*)

If set to `true`, file(or directory) modes will be kept even if a modified file is mounted. The option only affect the files which appear in `$ROOTFS_DIR`.

### ENABLE_INIT_VOLUMES_DATA (default=*true*)



### ENABLE_ROOTFS (default=*true*)

### ENABLE_CHMOD_FIX (default=*true*)

### ENABLE_UNSET_ENV_VARIBLES (default=*true*)

### ENABLE_PRE_RUN_SCRIPT (default=*true*)

### ENABLE_FORCE_INIT_VOLUMES_DATA (default=*false*)



### ASSETS_DIR (default=*/etc/docker-assets*)

### ROOTFS_DIR (default=*$ASSETS_DIR/rootfs*)

### CHECKLIST_FILE (default=*$ASSETS_DIR/checklist.md5*)

### DEFAULT_ENV_FILE (default=*$ASSETS_DIR/default-env.sh*)

### CHMOD_FILE (default=*$ASSETS_DIR/chmod.list*)

### BUILD_SCRIPT (default=*$ASSETS_DIR/build*)

### PRERUN_SCRIPT (default=*$ASSETS_DIR/pre-run*)

### VOLUMES_LIST (default=*$ASSETS_DIR/volumes.list*)

### VOLUMES_ARCHIVE (default=*$ASSETS_DIR/volumes.tar*)

### INITIALIZED_FLAG (default=*$ASSETS_DIR/initialized.flag*)

