class User < ApplicationRecord
  serialize :github_oauth_token, EncryptedColumn.new
end
