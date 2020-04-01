require 'yaml'
require 'colorize'
require 'singleton'

module R710_Tools
  class Fan_Control
    include Singleton

    # important config
    @@config_locations = ['/etc/custom-fan-control/speeds.yaml', 'speeds.yaml']
    @@inverval = 5            # time between checks in control loop
    @@max_manual_temp = 81    # switch back to automatic fan control at this temp
    @@cool_down_time = 120    # after switch to automatic wait that long before checking again

    @config = nil
    @is_manual = false
    @last_speed_set = 0
    @ipmitool = nil
    @last_core_temp = 0


    # load config on init
    def initialize
      @ipmitool = `which ipmitool`.strip
      raise 'ipmitool command not found' unless File.exist? @ipmitool
      @sensors = `which sensors`.strip
      raise 'sensors command not found' unless File.exist? @sensors
      @@config_locations.each do |loc|
        next unless File.exist?(loc)
        # puts "Loading configuration from #{loc}".colorize(:yellow)
        @config = YAML.load_file(loc)
        break
      end
      raise 'Did not find config file!' if @config.nil?
    end

    # get current cpu core temperature from sensors
    def get_temperature
      output = `#{@sensors}`
      max_temp = 0.0
      min_temp = 100
      output.each_line do |line|
        next unless line =~ /^Core.*\+(\d+\.\d+)°C\s+\(/
        t = Regexp.last_match(1).to_f
        max_temp = t if t > max_temp
        min_temp = t if t < min_temp
      end
      { min: min_temp, max: max_temp }
    end

    # get current ambient temp via ipmi
    def get_ambient
      output = `sudo #{@ipmitool} sdr get "Ambient Temp"`
      result = {}
      output.each_line do |line|
        if line =~ /Sensor Reading\s+:\s+(\d+)/
          result[:current] = Regexp.last_match(1).to_i
          next
        end
        if line =~ /Upper critical\s+:\s+(\d+)/
          result[:crit] = Regexp.last_match(1).to_i
          next
        end
        if line =~ /Upper non-critical\s+:\s+(\d+)/
          result[:warn] = Regexp.last_match(1).to_i
          next
        end
        if line =~ /Status\s+:\s+(\w+)/
          result[:status] = Regexp.last_match(1)
          next
        end
      end
      result
    end

    # get current fan speeds via ipmi
    def get_fan_speed
      output = `sudo #{@ipmitool} sdr type Fan`
      max_speed = 0
      min_speed = 15_000
      output.each_line do |line|
        next unless line =~ /(\d+)\s+RPM$/
        rpm = Regexp.last_match(1).to_i
        max_speed = rpm if rpm > max_speed
        min_speed = rpm if rpm < min_speed
      end
      { min: min_speed, max: max_speed }
    end

    # set the fan speed to the given percentage of max speed
    #
    # @param target fan speed in percent of max speed as integer
    def set_fan_speed(speed_percent, cur_temp)
      target_speed = format('%02X', speed_percent)
      system("sudo #{@ipmitool} raw 0x30 0x30 0x02 0xff 0x#{target_speed}")
      @last_speed_set = speed_percent
      puts "Fan speed set to #{speed_percent}% -> CPU Temp: #{cur_temp} C".colorize(:white).bold
    end

    # set fan speed control to manual
    def set_fan_manual
      system("sudo #{@ipmitool} raw 0x30 0x30 0x01 0x00")
      @is_manual = true
      puts 'Manual fan control active'
    end

    # set fan speed control to automatic
    def set_fan_automatic
      system("sudo #{@ipmitool} raw 0x30 0x30 0x01 0x01")
      @is_manual = false
      puts 'Automatic fan control restored'.colorize(:green)
    end

    # get target speed for current temperature
    #
    # @param current max cpu temperature as float
    def get_target_speed(temp)
      @config[:speed_steps].each do |range|
        return range[1] if range[0].cover?(temp)
      end
    end

    # the main loop adjusting fan speeds
    # check current temp against max manual temp
    # if above end manual control and switch back to automatic
    # -> wait for cool down period until we check again
    # else get the speed for the current temp and apply if != last set
    def fan_control_loop
      puts 'Starting fan control loop'.colorize(:white).bold
      begin
        loop do
          cur_temp = get_temperature[:max]
          if cur_temp > @@max_manual_temp
            puts 'Temperature higher than max_manual_temp -> switching to automatic'
            set_fan_automatic
            puts 'Cool down period started'
            sleep @@cool_down_time
            next
          end
          set_fan_manual unless @is_manual
          target = get_target_speed(cur_temp)
          set_fan_speed(target, cur_temp) if target != @last_speed_set
          puts "CPU Temp: #{cur_temp} C".colorize(:light_blue) if cur_temp != @last_core_temp
          @last_core_temp = cur_temp
          sleep @@inverval
        end
      rescue StandardError => e
        puts 'Exception or Interrupt occurred - switching back to automatic fan control'
        set_fan_automatic

        raise e
      end
    end
  end
end
