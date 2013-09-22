require "redis"
require "pry"

SOURCE_HOST = "ncbo-stg-app-21"
DST_HOST = "localhost"

def split_annotator()
  source = Redis.new(:host => SOURCE_HOST, :timeout => 60.0)
  dst = Redis.new(:host => DST_HOST, :timeout => 60.0)
  puts "Getting redis dict with #{source.hlen('dict')} entries ... "
  t0 = Time.now
  keys = source.hkeys("dict")
  puts "retrieved #{keys.length} in #{Time.new - t0} sec"
  keys.each_slice(100_000) do |slice_keys|
    t0 = Time.now
    slice_values = source.hmget("dict",slice_keys)
    puts "Obtained slice values #{slice_values.length} in #{Time.new - t0} sec"
    entries = []
    slice_keys.each_index do |i|
      key_entry = slice_keys[i]
      value_entry = slice_values[i]
      entries << [key_entry,value_entry]
    end
    dst.hmset "dict", *entries
    entries.each do |key_entry,value_entry|
      dst.hmset key_entry, *((source.hgetall key_entry).to_a)
    end
    puts "next slice"
  end
end

split_annotator
