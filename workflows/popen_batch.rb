require_relative '../settings'

require 'logger'
require 'progressbar'
require 'open3'


command_file = ARGV[0]
logger = Logger.new(ARGV[1])

commands = []
File.open(command_file,"r").each_line do |command|
  commands << command
end
progress = ProgressBar.new("running commands ",commands.length)
commands.each do |cmd|
  stdout,stderr,status = Open3.capture3(cmd)
  logger.info(stdout)
  logger.info(stderr)
  if not status.success?
    puts "error running `#{cmd}`"
  end
  progressbar.inc
end
logger.close
