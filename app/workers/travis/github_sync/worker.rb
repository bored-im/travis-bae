module Travis
  module GithubSync
    class Worker
      include Sidekiq::Worker

      def perform(event, payload)
        case event
        when "sync_user"
          sync_user(payload)
        else
          raise "Unknown event #{event}"
        end
      end

      private

      def sync_user(payload)
        user = User.find(payload["user_id"])
        github_token = user.github_oauth_token

        client = Octokit::Client.new(access_token: github_token)
        client.repos.each do |repo|
          gh_repo = Repository.find_or_initialize_by(github_id: repo[:id])
          gh_repo.update_attributes!(
            name: repo[:name], url: repo[:html_url],
            owner_name: repo[:owner][:login],
            owner_type: repo[:owner][:type],
            owner_id: repo[:owner][:id],
            github_id: repo[:id],
            default_branch: repo[:default_branch],
            github_language: repo[:language])
        end

        user.update_attributes!(synced_at: Time.current,
                                is_syncing: false)
      end
    end
  end
end
