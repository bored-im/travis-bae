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
        orgs = client.orgs.each do |gh_org|
          org = Organization.find_or_initialize_by(github_id: gh_org[:id])
          org.update_attributes!(
            name: gh_org[:name],
            login: gh_org[:login],
            avatar_url: gh_org[:avatar_url],
            location: gh_org[:location],
            email: gh_org[:email],
            company: gh_org[:company],
            homepage: gh_org[:homepage]
            )
          org.memberships.find_or_create_by!(user_id: user.id)
        end

        client.repos.each do |gh_repo|
          repo = Repository.find_or_initialize_by(github_id: gh_repo[:id])
          owner =
            case gh_repo[:owner][:type]
            when "Organization"; Organization.find_by(github_id: gh_repo[:owner][:id])
            when "User"; User.find_by(github_id: gh_repo[:owner][:id])
            else raise "Unknown owner type #{repo[:owner][:type]}"
            end

          repo.update_attributes!(
            name: gh_repo[:name],
            url: gh_repo[:html_url],
            owner_name: gh_repo[:owner][:login],
            owner: owner,
            github_id: gh_repo[:id],
            default_branch: gh_repo[:default_branch],
            github_language: gh_repo[:language])

          permission = repo.permissions.find_or_initialize_by(user_id: user.id)
          permission.update_attributes!(
            admin: gh_repo[:permissions][:admin],
            push: gh_repo[:permissions][:push],
            pull: gh_repo[:permissions][:pull])
        end

        user.update_attributes!(synced_at: Time.current,
                                is_syncing: false)
      end
    end
  end
end
