require_relative 'settings'

require 'pry'
require 'redis'
require 'zlib'

chunk_size = 10_000 # in lines
num_threads = 4

tsv_path = File.expand_path("../id_mappings_classes.tsv", __FILE__)
unless File.file?(tsv_path)
  exit("id_mappings_classes.tsv does not exist, please run id_mappings_classes_tsv_from_obs.rb")
end

redis = Redis.new(host: LinkedData.settings.redis_host, port: LinkedData.settings.redis_port, timeout: 60)

# Delete old keys
keys = redis.smembers("old:classes:keys")
puts "Deleting #{keys.length} class mapping entries"
keys.each_slice(500_000) {|chunk| redis.del chunk}
redis.del "old:classes:keys"

line_count = %x{wc -l #{tsv_path}}.split.first.to_i
puts "Starting redis store for #{line_count} classes"

start = Time.now
line_chunks = []
File.foreach(tsv_path).each_slice((line_count.to_f / num_threads.to_f).ceil) do |chunk|
  line_chunks << chunk.dup
end

# Parse out data from file
threads = []
data = []
parse_data = Time.now
line_splitter = Regexp.new(/(.*)\t(.*)\t(.*)/)
num_threads.times do |i|
  threads << Thread.new do
    chunk = line_chunks.pop
    chunk.each_slice(chunk_size) do |lines|
      lines.each do |line|
        acronym, short_id, uri = line.scan(line_splitter).first
        hashed_uri = Zlib::crc32(uri)
        short_id_key = "old:#{acronym}:#{short_id}"

        data << [acronym, short_id, uri, hashed_uri, short_id_key]
      end
    end
  end
end
# Wait for completion
threads.each {|t| t.join}
puts "Parsing took #{Time.now - parse_data}s"

# Store to redis
threads = []
count = 0
store_redis = Time.now
num_threads.times do |i|
  threads << Thread.new do
    data.each_slice(chunk_size) do |lines|
      redis.pipelined do
        lines.each do |line|
          acronym, short_id, uri, hashed_uri, short_id_key = line

          # Short id to URI mapping
          redis.set short_id_key, uri

          # We could hit collisions with crc32, so we bucket the hashes
          # then we can iterate over them when doing lookup by URI
          redis.lpush hashed_uri, short_id_key

          # Store keys in a set for delete
          redis.sadd "old:classes:keys", short_id_key
          redis.sadd "old:classes:keys", hashed_uri

          count += 1
        end
      end
    end
  end
end
# Wait for completion
threads.each {|t| t.join}
puts "Storing took #{Time.now - store_redis}s"

puts "Took #{Time.now - start}s to store #{count} class mappings"