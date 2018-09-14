class Job < ApplicationRecord
  belongs_to :source, polymorphic: true
  belongs_to :owner, polymorphic: true

  class Test < ::Job
  end
end
