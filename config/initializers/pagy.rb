# Pagy initializer file
require "pagy/extras/overflow"

Pagy::DEFAULT[:limit] = 20  # items per page
Pagy::DEFAULT[:overflow] = :last_page  # Redirect to last page if page param is out of range
