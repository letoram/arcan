#!/usr/bin/ruby
# treat STDIN as using some statusbar protocol, and split it up into
# multiple subprocesses that attach using arcan-trayicon to whatever
# ARCAN_CONNPATH was set before.
#
group_token = "|" # set based on protocol
parse_method = :lemon

class Trayicon
  def initialize(arg)
    @process = IO.popen("arcan-trayicon --stdin #{arg}", "r+")
    Thread.new{
      @process.each_line{|line| STDOUT.print(line) }
    }
  end

# lemonbar format:
#
  def lemon(msg)
    @process.print("#{msg}\n")
  rescue
    STDERR.print("arcan connection lost")
    exit
  end
end

# allocate, read, process and forward to the right parser
slots = {}
STDIN.each_line do |a|
  blocks = a.strip.split(group_token)
  blocks.each_index{|i|
    if not slots[i] then
      slots[i] = Trayicon.new("#{ARGV[1..-1].join(" ")}")
    end
    slots[i].send(parse_method, blocks[i])
  }
end
