class Build < ApplicationRecord
  belongs_to :owner, polymorphic: true
end
