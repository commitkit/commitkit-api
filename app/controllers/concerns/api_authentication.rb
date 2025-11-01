module ApiAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_with_api_token!
  end

  private

  def authenticate_with_api_token!
    token = request.headers["Authorization"]&.gsub(/^Bearer /, "")
    @current_user = User.find_by(api_token: token)

    unless @current_user
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  attr_reader :current_user
end
