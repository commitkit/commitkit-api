require 'rails_helper'

RSpec.describe "Registrations", type: :request do
  describe "GET /registration/new" do
    it "returns success" do
      get new_registration_path
      expect(response).to have_http_status(:success)
    end
    
    it "displays signup form" do
      get new_registration_path
      expect(response.body).to include("Sign up for CommitKit")
    end
  end
  
  describe "POST /registration" do
    context "with valid params" do
      let(:valid_params) do
        {
          user: {
            email_address: "newuser@example.com",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
      
      it "creates a new user" do
        expect {
          post registration_path, params: valid_params
        }.to change(User, :count).by(1)
      end
      
      it "generates an API token for the user" do
        post registration_path, params: valid_params
        
        user = User.find_by(email_address: "newuser@example.com")
        expect(user.api_token).to be_present
        expect(user.api_token.length).to be > 20
      end
      
      it "logs in the user" do
        post registration_path, params: valid_params
        
        follow_redirect!
        expect(response.body).to include("newuser@example.com")
      end
      
      it "redirects to dashboard" do
        post registration_path, params: valid_params
        expect(response).to redirect_to(root_path)
      end
    end
    
    context "with invalid params" do
      it "does not create user with mismatched passwords" do
        expect {
          post registration_path, params: {
            user: {
              email_address: "test@example.com",
              password: "password123",
              password_confirmation: "different"
            }
          }
        }.not_to change(User, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
      end
      
      it "does not create user with duplicate email" do
        User.create!(email_address: "existing@example.com", password: "password123", password_confirmation: "password123")
        
        expect {
          post registration_path, params: {
            user: {
              email_address: "existing@example.com",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)
      end
      
      it "does not create user without email" do
        expect {
          post registration_path, params: {
            user: {
              email_address: "",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)
      end
    end
  end
end
