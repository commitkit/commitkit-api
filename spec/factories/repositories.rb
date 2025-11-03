FactoryBot.define do
  factory :repository do
    association :user
    url { Faker::Internet.url }
  end
end
