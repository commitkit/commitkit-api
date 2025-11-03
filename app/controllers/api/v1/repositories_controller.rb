module Api
  module V1
    class RepositoriesController < BaseController
      def index
        repositories = current_user.repositories
        repositories = repositories.where(url: params[:url]) if params[:url].present?
        render json: repositories, status: :ok
      end

      def create
        repository = current_user.repositories.find_or_create_by!(url: params[:url])

        synced = 0
        skipped = 0

        params[:commits].each do |commit_data|
          if current_user.commits.exists?(commit_hash: commit_data[:commit_hash])
            skipped += 1
            next
          end

          current_user.commits.create!(
            repository: repository,
            commit_hash: commit_data[:commit_hash],
            message: commit_data[:message],
            summary: commit_data[:summary]
          )
          synced += 1
        end

        render json: { synced: synced, skipped: skipped, failed: 0 }, status: :created
      end

      def destroy
        repository = current_user.repositories.find_by(id: params[:id])

        if repository
          repository.destroy
          render json: { message: 'Repository and all associated commits deleted successfully' }, status: :ok
        else
          render json: { error: 'Repository not found' }, status: :not_found
        end
      end
    end
  end
end
