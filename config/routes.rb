Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: [ :new, :create ]

  # Friendly URL aliases
  get "/login", to: "sessions#new", as: :login
  get "/signup", to: "registrations#new", as: :signup

  # Landing page and dashboard
  root "home#index"
  get "/dashboard", to: "dashboard#index", as: :dashboard
  get "/settings", to: "settings#index", as: :settings

  # AI Summaries
  resources :ai_summaries, only: [:create]

  # API routes
  namespace :api do
    namespace :v1 do
      resources :commits, only: [ :index, :create, :destroy ] do
        collection do
          post :generate_cv_bullets
          post :generate_ai_summaries
        end
      end
      resources :repositories, only: [ :index, :create, :destroy ]
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
