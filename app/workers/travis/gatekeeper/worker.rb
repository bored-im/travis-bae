require 'travis/yaml'

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
        owner = User.find_or_create_by!(login: payload["pusher"]["name"])
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
        build.update_attributes!(number: build.id)

        create_jobs!(repository, commit, owner, build)
      end

      def create_jobs!(repository, commit, owner, build)
        matrix_array = travis_matrix(repository, commit)
        matrix = matrix_array.rows.first

        if matrix["matrix"].present?
          matrix["matrix"]["include"].each_with_index do |matrix_config, index|
            job_config_json =
              matrix
              .slice("dist", "group", "addons")
              .merge(matrix_config)
              .merge(os: "linux") # TODO: This can be other OS also

            create_job_with_config(repository, commit, build, owner,
                                   job_config_json, index + 1)
          end
        else
          create_job_with_config(repository, commit, build, owner,
                                 matrix, 1)
        end
      end

      def config
        file = File.expand_path('config/travis.yml')
        env = ENV['RAILS_ENV']
        YAML.load_file(file)[env]
      end

      def travis_matrix(repository, commit)
        gh_oauth = config["oauth2"]
        gh_client_id = gh_oauth["client_id"]
        gh_client_secret = gh_oauth["client_secret"]

        repo_url = "https://api.github.com/repos/" + repository.owner_name + "/" + repository.name
        travis_yaml_url = repo_url + "/contents/.travis.yml?ref=#{commit.commit}"
        gh_url = travis_yaml_url + "&client_secret=" + gh_client_secret +
                                   "&client_id=" + gh_client_id

        response1 = Faraday.get(gh_url)
        raw_url = JSON.parse(response1.body)["download_url"]
        response2 = Faraday.get(raw_url)
        travis_yaml = response2.body
        travis_yaml_json = YAML.load(travis_yaml)
        Travis::Yaml.matrix(travis_yaml_json)
      end

      def create_job_with_config(repository, commit, build, owner,
                                 job_config_json, index)
        job_config = JobConfig.create!(repository_id: repository.id, key: 'key',
                                       config: job_config_json)
        Job.create!(
          repository_id: repository.id,
          commit_id: commit.id,
          source: build,
          state: "created",
          number: "#{build.number}.#{index}",
          owner: owner,
          config_id: job_config.id)
      end
    end
  end
end
