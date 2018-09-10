module Travis
  module Gatekeeper
    class Worker
      include Sidekiq::Worker

      def perform(message)
        case message["type"]
        when "push"
          payload = JSON.parse(message["payload"])
          create_build_from_push(payload)
        else
          raise "Unknown event #{message}"
        end
      end

      private

      def create_build_from_push(payload)
        repository = Repository.find_by!(github_id: payload["repository"]["id"])
        owner = User.find_by!(login: payload["pusher"]["name"])
        commit = Commit.find_or_initialize_by(commit: payload["head_commit"]["id"])
        commit.update_attributes!(
          repository_id: repository.id,
          ref: payload["ref"],
          branch: payload["ref"].split("/").last,
          message: payload["head_commit"]["message"],
          compare_url: payload["compare"],
          committed_at: Time.zone.parse(payload["head_commit"]["timestamp"]),
          committer_name: payload["head_commit"]["committer"]["name"],
          committer_email: payload["head_commit"]["committer"]["email"],
          author_name: payload["head_commit"]["author"]["name"],
          author_email: payload["head_commit"]["author"]["email"],
          )

        request = Request.find_or_initialize_by(commit_id: commit.id)
        request.update_attributes!(
          repository_id: repository.id,
          state: "created",
          event_type: "push",
          base_commit: payload["before"],
          head_commit: payload["after"],
          owner: owner)

        build = Build.find_or_initialize_by(request_id: request.id)
        build.update_attributes!(
          commit_id: commit.id,
          repository_id: repository.id,
          owner: owner,
          committed_at: Time.zone.parse(payload["head_commit"]["timestamp"]),
          committer_name: payload["head_commit"]["committer"]["name"],
          committer_email: payload["head_commit"]["committer"]["email"],
          author_name: payload["head_commit"]["author"]["name"],
          author_email: payload["head_commit"]["author"]["email"],
          event_type: "push",
          ref: payload["ref"],
          branch: payload["ref"].split("/").last,
          compare_url: payload["compare"],
          state: "created")

        job = Job.create!(
          repository_id: repository.id,
          commit_id: commit.id,
          source: build,
          state: "created",
          owner: owner)
      end
    end
  end
end
