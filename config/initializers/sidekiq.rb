Sidekiq.configure_server do |config|
  config.redis = { namespace: "sidekiq", url: ENV.fetch("TRAVIS_BAE_REDIS_URL") }
end

Sidekiq.configure_client do |config|
  config.redis = { namespace: "sidekiq", url: ENV.fetch("TRAVIS_BAE_REDIS_URL") }
end
