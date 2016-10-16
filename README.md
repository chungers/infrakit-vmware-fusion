InfraKit Instance Plugin for VMWare Fusion
==========================================

## Status

POC only.

This is a proof of concept of an instance plugin for [InfraKit](https://github.com/docker/infrakit).
Currently you can use this plugin with a plain vanilla flavor plugin and the default group plugin to
manage a group of VMs via VMWare Fusion (which runs on the Mac and Windows).  You can scale up/down and suspend
VM instances and see new instances get created to ensure group size.

This is built on [VIX](http://blogs.vmware.com/vix/) using an open source Golang C-binding of the API.  So building
and running requires some special care (for cgo and requires dynamic linking).

VM instances are created by 'cloning' an existing `vmx` file.  VMX files are expected to be stored on disk as
children in the top level directory specified by the `--vm-lib` flag on start up of the plugin.

States of indivdual VM instances are stored as subdirectories of a top level directory specified by the `--vm-dir` flag
on startup of the plugin.

You can create your own VM using whatever image you want.  Then copy the whole directory (using the `${name}.vmwarevm`)
into the vm lib folder (see `./vmx`).  Then in your JSON, just reference this basename of the vmx.
See example below.

## Limitations

Currently, it's not possible to perform cloudinit-like execution of init scripts unless they are baked into the image.
It would be nice to be able to inject the scripts via the Flavor plugin, but the VIX API requires the [VM Tools](https://blogs.vmware.com/vsphere/2015/09/vmware-tools-10-0-0-released.html)
driver sets for the guest OS and there are only limited support for popular gues OSes.

We could use SSH with a baked-in SSH key and then disable SSH after the init scripts are run.  Again, this requires
special preparation of the iso and the vmx, and we'd have to do this outside the VIX API.  It's possible but not implemented
currently since that would require support by the guest OS and preparing the images.


## Building

```shell
make plugins
```

This will put a binary in `build`

Note that there are some ISOs missing and you need to make sure they are in the `iso/` directory.

```shell
make vmx-alpine
```
will download an iso image from alpine repo and place that in the `iso/` directory.
A `.vmx` file will be generated off the template using the absolute path of the iso file.

If you have access to mobylinux, change the `Makefile` to clone from the correct repo, and run
`make qemu-iso`.  Place the built iso in the `iso/` directory and do

```shell
make vmx-moby
```

This will generate a vmx file using the correct absolute path that points to the mobylinux iso.

## Running

*For Go 1.6 or above -- You need to set an environment variable to disable cgo's dynamic checking*.

```shell
export GODEBUG=cgocheck=0
```

```shell
# On OSX
export DYLD_LIBRARY_PATH=$(pwd)/vendor/libvix
```

```shell
# On linux
export LD_LIBRARY_PATH=$(pwd)/vendor/libvix
```

From the current directory (repo root), run

```shell
./build/infrakit-instance-vmware-fusion --log=5 --vm-dir=./vms --vm-lib=./vmx
```

The flag `--vm-dir` is where the vm instances will be placed (their state, vmdk, etc.), and
`--vm-lib` is the top level directory where templated vmx directories are.

When the plugin provisions a new instance, it uses the `VMX` field in the config and the
`--vm-lib` flag to determine where the VMX file can be found.  It uses this rule...
Given the `--vm-lib` flag as `${vmlib}` and the `VMX` field in the following JSON for managing
a group (using the default group plugin and `vanilla` flavor):

```json
{
    "ID": "vmware_fusion_demo",
    "Properties": {
        "Instance" : {
            "Plugin": "vmware-fusion",
            "Properties": {
                "Tags" : {
                    "env" : "dev",
                    "instance-plugin" : "fusion"
                },
                "VMX" : "alpine-3.4.4",
                "MemorySizeMBs" : 512,
                "NumCPUs" : 2,
                "LaunchGUI" : true
            }
        },
        "Flavor" : {
            "Plugin": "flavor-vanilla",
            "Properties": {
                "Size" : 5
            }
        }
    }
}
```

The VMX file path will be computed as `${vmlib}/${VMX}.vmwarevm/${VMX}.vmx`.

Once the VMX file is located, it is cloned to provision a new instance.  The state of the new VM will
be placed in the `--vm-dir` subdirectory.

This provides a simple mechanism for supporting different image types.
