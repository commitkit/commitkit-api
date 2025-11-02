class ApplicationMailer < ActionMailer::Base
  default from: "CommitKit <noreply@commitkit.dev>"
  layout "mailer"
end
