package main

import (
	"encoding/json"
	"fmt"
	"os"

	log "github.com/Sirupsen/logrus"
	"github.com/chungers/infrakit-vmware-fusion"
	"github.com/docker/infrakit/plugin/util"
	instance_plugin "github.com/docker/infrakit/spi/http/instance"
	"github.com/spf13/cobra"
)

var (
	// Version is the build release identifier.
	Version = "Unspecified"

	// Revision is the build source control revision.
	Revision = "Unspecified"
)

func main() {

	logLevel := len(log.AllLevels) - 2
	listen := "unix:///run/infrakit/plugins/vmware-fusion.sock"

	homeDir := os.Getenv("HOME")

	// VMWare Fusion VIX API flags
	vmDir := homeDir + "/Documents/Virtual Machines.localized"
	vmLib := homeDir + "/Documents/Virtual Machines.localized"

	cmd := &cobra.Command{
		Use:   os.Args[0],
		Short: "VMWare Fusion instance plugin",
		RunE: func(c *cobra.Command, args []string) error {

			if logLevel > len(log.AllLevels)-1 {
				logLevel = len(log.AllLevels) - 1
			} else if logLevel < 0 {
				logLevel = 0
			}
			log.SetLevel(log.AllLevels[logLevel])

			if c.Use == "version" {
				return nil
			}

			instancePlugin, err := fusion.NewInstancePlugin(vmDir, vmLib)
			if err != nil {
				log.Error(err)
				return err
			}

			log.Infoln("Starting plugin")
			log.Infoln("Listening on:", listen)

			_, stopped, err := util.StartServer(listen, instance_plugin.PluginServer(instancePlugin),
				func() error {
					instancePlugin.Shutdown()
					return nil
				},
			)

			if err != nil {
				log.Error(err)
			}

			<-stopped // block until done

			log.Infoln("Server stopped")
			return nil
		},
	}

	cmd.AddCommand(&cobra.Command{
		Use:   "version",
		Short: "print build version information",
		RunE: func(cmd *cobra.Command, args []string) error {
			buff, err := json.MarshalIndent(map[string]interface{}{
				"version":  Version,
				"revision": Revision,
			}, "  ", "  ")
			if err != nil {
				return err
			}
			fmt.Println(string(buff))
			return nil
		},
	})

	cmd.Flags().StringVar(&listen, "listen", listen, "listen address (unix or tcp) for the control endpoint")
	cmd.Flags().IntVar(&logLevel, "log", logLevel, "Logging level. 0 is least verbose. Max is 5")

	cmd.Flags().StringVar(&vmDir, "vm-dir", vmDir, "Directory where VM states are stored")
	cmd.Flags().StringVar(&vmLib, "vm-lib", vmLib, "Path to the vm library where vmx folders are found")

	err := cmd.Execute()
	if err != nil {
		log.Error(err)
		os.Exit(1)
	}
}
