# r710-fan-control

This is a modified fork of `sulaweyo/r710-fan-control`. I really only changed some small things, nothing major.

### Install

1.  install software

    -   ruby and ruby gem

    -   `sudo apt install -y ruby ruby-devel rubygems lm_sensors ipmitool`
    -   `gem thor colorize`

2.  modify the config in `Fan_Control.rb`

3.  modify the fan speeds in `speeds.yaml`. Right now the speeds are optimized to keep the temp below 73° on a 24/7 high cpu load so you may want something more conservative:

 ```yaml
:speed_steps:
      !ruby/range 0..40: 15   # run at 10% speed up to 30°C
      !ruby/range 41..50: 20  # run at 15% speed up to 40°C
      !ruby/range 51..55: 30  # run at 20% speed up to 50°C
      !ruby/range 56..60: 35  # run at 30% speed up to 60°C
      !ruby/range 61..66: 40  # run at 40% speed up to 65°C
 ```


4.  run with `ipmi-fancontrol.rb start`. The script has a help command too

### Notes

Be careful with this. If you mess up and the script dies or whatever the fans could be stuck at the wrong speed and your cpus can melt lol. Running this as a service will almost 100% avoid this because of the auto-restart features and `ExecStopPost`. I trust it and I had it running for months so there's really no worry unless you decide to use this in production.

Use `watch -n1 "sensors | grep core"` to watch the cpu temps and modify the speed config

If you are going to use this as a service, install the file`fan-control.service`. Make sure to modify it for your specific OS.

* * *

# r710-fan-control

If you run your R710 in a dedicated server room noise won't be an issue for you. If you have a R710 in your flat the situation is a bit different as per default the fans ramp up pretty fast and the noise level goes up with them. Mine actually never goes below 3.6k RPM which is still acceptable but the slightest increase in load will get at least some fans up to 6k RPM and that is very noticeable.

### How does it work?

While searching for a solution to this problem i stumbled across some scripts by [@NoLooseEnds](https://github.com/NoLooseEnds) that set the speed to a defined value: [R710-IPMI-TEMP](https://github.com/NoLooseEnds/Scripts/tree/master/R710-IPMI-TEMP)

Based on that i started playing around with the ipmitool and wrote this tool in Ruby that can be used to set a specific value but as well to actually monitor the cpu core temperature and ramp up the fans accordingly. To do that you can configure which fan speed should be applied at which temperature and just let it run. If the cpu temperature goes above the defined max temperature it will switch back to Dell's automatic mode. This will bring the temperature back down to a reasonable value and after a configurable cool down period we start again with our fan speeds.

### Prerequisites

**In IDRAC**
In order to read and set fan speeds idrac needs to be enabled and ipmi needs to be reachable.

**In the OS**
This tool is written in Ruby so _Ruby_ and some gems are needed:

-   _thor_ for the cli
-   _colorize_ as I like color output

_ipmitool_ needs to be installed and on the PATH

_lm_sensors_ needs to be installed and configured

### Configuration

Check out the sample config file

```yaml
---
# configuration file for sulaweyo/r710-fan-control
:user: 'your user'      # idrac user
:pass: 'your password'  # idrac password
:host: 'your idrac ip'  # idrac ip
:interval: 5            # time between checks in control loop
:max_manual_temp: 66    # switch back to automatic fan control at this temp
:cool_down_time: 120    # after switch to automatic wait that long before checking again
# the following hash defines fan speed values and the temp rang that is ok for that speed
:speed_steps:
  !ruby/range 0..40: 15   # run at 15% speed up to 30°C
  !ruby/range 41..50: 20  # run at 20% speed up to 40°C
  !ruby/range 51..55: 30  # run at 30% speed up to 50°C
  !ruby/range 56..60: 35  # run at 35% speed up to 60°C
  !ruby/range 61..65: 40  # run at 40% speed up to 65°C
```

Obviously you can adjust all these values to your liking or add/remove speed steps. Just make sure to really test how the temperatures develop along with these values!

### Installation

Check out the script to wherever you like and run 'bundler install' in that directory to get the required gems. After that run './Fan-Control-CLI.rb' to see available commands.

    ./Fan-Control-CLI.rb
    Commands:
      Fan-Control-CLI.rb fanspeed          # Get the current fan speed
      Fan-Control-CLI.rb help [COMMAND]    # Describe available commands or one specific command
      Fan-Control-CLI.rb reset             # Switch back to automatic fan control
      Fan-Control-CLI.rb setspeed [value]  # Set fan speed to given percent of max speed
      Fan-Control-CLI.rb start             # Start fan control loop
      Fan-Control-CLI.rb temp              # Get current cpu core temperature

To run it as a service a systemd unit is included but you need to update location and user before starting it. Copy or link it to '/etc/systemd/system/', run 'systemctl daemon-reload' to make systemd aware of the new service and then start/enable it.

### Disclaimer

The sample values seem to work fine for me but I cannot emphasise enough that you need to test what works for you. The script disables the built in fan control and that can lead to damage!

**I take NO responsibility if you mess up anything.**
