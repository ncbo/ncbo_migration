require_relative '../settings'

require 'logger'
require 'progressbar'

redis = Redis.new host: $REDIS_GOO_HOST, port: $REDIS_GOO_PORT, timeout: 60
graphs = redis.smembers "sparql:graphs"
query_graph = {}
graphs.each do |g|
  queries = redis.smembers("#{g}")
  if queries.length > 100
    query_graph[g] = queries
    puts "#{g} --> #{queries.length}" 
  end
end
queries_sorted = query_graph.to_a.sort_by { |g,q| q.length }.reverse
queries_sorted.each do |g,q|
  remove = (q.length * 0.20).to_i
  to_flush = q[0..remove]
  to_flush.each do |qhash|
    redis.del(qhash)
  end
  redis.srem("sparql:queries",*to_flush)
  sleep(5)
end
binding.pry
