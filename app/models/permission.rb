class Permission < ApplicationRecord
  ROLES = %w(admin push pull)

  belongs_to :user
end
