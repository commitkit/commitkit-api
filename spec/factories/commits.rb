FactoryBot.define do
  factory :commit do
    user { nil }
    commit_hash { "MyString" }
    message { "MyText" }
    summary { "MyText" }
  end
end
