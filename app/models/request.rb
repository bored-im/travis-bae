class Request < ApplicationRecord
  belongs_to :owner, polymorphic: true

  serialize :token, EncryptedColumn.new(disable: true)
end
