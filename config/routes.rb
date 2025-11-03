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

  # API routes
  namespace :api do
    namespace :v1 do
      resources :commits, only: [ :index, :create, :destroy ]
      resources :repositories, only: [ :index, :create, :destroy ]
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
