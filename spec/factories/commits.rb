FactoryBot.define do
  factory :commit do
    association :user
    sequence(:commit_hash) { |n| Faker::Crypto.sha1 }
    message { Faker::Lorem.sentence }
    summary { Faker::Lorem.sentence(word_count: 5) }
  end
end
