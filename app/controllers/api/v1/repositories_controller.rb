module Api
  module V1
    class RepositoriesController < BaseController
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
