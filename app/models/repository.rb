class Repository < ApplicationRecord
  belongs_to :owner, polymorphic: true, optional: true

  has_many :permissions, dependent: :delete_all
  has_many :users, through: :permissions
end
