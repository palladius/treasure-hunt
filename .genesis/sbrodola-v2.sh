#!/bin/bash
# sbrodola.sh - Generates the TrHuGa Rails application (v2)

# Stop at the first big error - a treasure hunter's motto!
set -euo pipefail

#APP_NAME="trhuga"
APP_NAME="treasure-hunt-game-v2" # Specify your app name
RUBY_VERSION="3.4.4" # Specify your target Ruby version
RAILS_VERSION_CONSTRAINT="~> 8.0.2" # Specify your target Rails version constraint for Gemfile

# --- Helper Functions ---
bold=$(tput bold)
normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)

log() {
  echo "${bold}${green}>>> ${1}${normal}"
}

warn() {
  echo "${bold}${yellow}!!! ${1}${normal}"
}

info() {
  echo "${bold}${blue}--- ${1}${normal}"
}

# --- Check for Rails ---
if ! command -v rails &> /dev/null
then
    warn "Rails command could not be found. Please install Rails (ideally matching ${RAILS_VERSION_CONSTRAINT}) and Ruby ${RUBY_VERSION}."
    exit 1
fi
if ! command -v bundle &> /dev/null
then
    warn "Bundler command could not be found. Please ensure Bundler is installed (gem install bundler)."
    exit 1
fi


log "Starting TrHuGa Rails App Generation (v2)..."

# --- Create Rails App ---
info "Generating new Rails app: ${APP_NAME}"
# -T skips Test::Unit files. Rails 8 might have different default test framework setup.
# We will add rspec gems later.
rails new "${APP_NAME}" --database=postgresql --css=tailwind --javascript=importmap -T

# --- Navigate into App Directory ---
cd "${APP_NAME}"
log "Changed directory to $(pwd)"

# --- Set Ruby Version ---
info "Setting Ruby version to ${RUBY_VERSION} in .ruby-version"
echo "${RUBY_VERSION}" > .ruby-version

# --- Ensure Rails version in Gemfile (if needed) ---
# rails new should set this, but we can make sure it matches our constraint.
# This is a bit more surgical than overwriting the whole file.
# It assumes rails new adds a line like: gem "rails", "~> 8.0.0.alpha"
# We'll update it if it doesn't precisely match RAILS_VERSION_CONSTRAINT
# or add it if somehow missing (highly unlikely).
if grep -q "gem \"rails\"" Gemfile; then
    sed -i.bak "s|gem \"rails\",.*|gem \"rails\", \"${RAILS_VERSION_CONSTRAINT}\"|g" Gemfile && rm Gemfile.bak
else
    echo "gem \"rails\", \"${RAILS_VERSION_CONSTRAINT}\"" >> Gemfile
fi
# Also ensure the ruby version directive is present and correct at the top
if grep -q "ruby \".*\"" Gemfile; then
    sed -i.bak "s|ruby \".*\"|ruby \"${RUBY_VERSION}\"|g" Gemfile && rm Gemfile.bak
else
    # Prepend ruby version if not found (unlikely for modern rails new)
    echo "ruby \"${RUBY_VERSION}\"" | cat - Gemfile > temp_gemfile && mv temp_gemfile Gemfile
fi


# --- Add Gems Surgically using bundle add ---
log "Adding necessary gems using 'bundle add'..."

# Devise for authentication
info "Adding Devise..."
bundle add devise --version "~> 4.9"

# For LLM interaction (Gemini)
info "Adding Gemini AI gem..."
bundle add gemini-ai --version "~> 4.2.0" # As specified

# HTTP client (still useful)
info "Adding HTTP gem..."
bundle add http --version "~> 5.1" # Example version, check latest

# For PDF Generation
info "Adding Prawn and Prawn-Table for PDF generation..."
bundle add prawn --version "~> 2.4"
bundle add prawn-table --version "~> 0.2.2"

# For .env file management in development/test
info "Adding Dotenv-Rails for development and test groups..."
bundle add dotenv-rails --group "development, test" --version "~> 2.8"

# Testing gems (RSpec, FactoryBot, Faker)
info "Adding RSpec, FactoryBot, and Faker for development and test groups..."
bundle add rspec-rails --group "development, test" --version "~> 6.1"
bundle add factory_bot_rails --group "development, test" --version "~> 6.2" # Check for latest compatible
bundle add faker --group "development, test" --version "~> 3.2"

# Note: `pg` should be added by `rails new --database=postgresql`.
# `puma`, `turbo-rails`, `stimulus-rails`, `tailwindcss-rails`, `debug`, `bootsnap`, `web-console`
# are typically included by `rails new` with the options used.
# `bundle install` will be run implicitly by `bundle add` or run it once at the end.

log "Running final bundle install to ensure all is good..."
bundle install

# --- Install Tailwind CSS (already invoked by rails new --css=tailwind, but ensure config) ---
log "Ensuring Tailwind CSS is configured..."
# rails tailwindcss:install # This command is run by `rails new --css=tailwind`.
# We need to ensure the `application.tailwind.css` and `tailwind.config.js` exist.
# `rails new` should have created these. If not, the command would be:
# bundle exec rails tailwindcss:install

# --- Devise Setup ---
log "Setting up Devise..."
bundle exec rails g devise:install

info "Creating User model with Devise..."
bundle exec rails g devise User is_admin:boolean:default_false language:string

# --- Generate Models ---
log "Generating models..."

info "Generating Game model..."
bundle exec rails g model Game name:string public_code:string:uniq start_date:datetime end_date:datetime published:boolean default_clue_type:integer context:text user:references

info "Generating Clue model..."
bundle exec rails g model Clue series_id:integer unique_code:string parent_advisory:text published:boolean clue_type:integer question:string answer:string visual_description:string next_clue_riddle:text location:string geo_x:float geo_y:float location_addon:string game:references

info "Generating PlayerProgress model..."
bundle exec rails g model PlayerProgress game:references nickname:string language:string current_clue_series_id:integer unlocked_clue_series_ids:text player_token:string:uniq

# --- Add Indexes and Defaults in Migrations ---
log "Updating migrations for indexes and default values..."
# Find the create_games migration file
GAME_MIGRATION_FILE=$(ls db/migrate/*_create_games.rb | head -n 1)
sed -i.bak "/t.string :public_code/a \ \ \ \ add_index :games, :public_code, unique: true" "$GAME_MIGRATION_FILE"
sed -i.bak 's/t.boolean :published/t.boolean :published, default: true/' "$GAME_MIGRATION_FILE" && rm "${GAME_MIGRATION_FILE}.bak"

# Find the create_clues migration file
CLUE_MIGRATION_FILE=$(ls db/migrate/*_create_clues.rb | head -n 1)
sed -i.bak "/t.references :game, null: false, foreign_key: true/a \ \ \ \ add_index :clues, [:game_id, :unique_code], unique: true\n \ \ \ \ add_index :clues, [:game_id, :series_id], unique: true" "$CLUE_MIGRATION_FILE"
sed -i.bak 's/t.boolean :published/t.boolean :published, default: true/' "$CLUE_MIGRATION_FILE" && rm "${CLUE_MIGRATION_FILE}.bak"

# Find the create_player_progresses migration file
PLAYER_PROGRESS_MIGRATION_FILE=$(ls db/migrate/*_create_player_progresses.rb | head -n 1)
sed -i.bak "/t.string :player_token/a \ \ \ \ add_index :player_progresses, :player_token, unique: true" "$PLAYER_PROGRESS_MIGRATION_FILE"
sed -i.bak 's/t.integer :current_clue_series_id/t.integer :current_clue_series_id, default: 1/' "$PLAYER_PROGRESS_MIGRATION_FILE" && rm "${PLAYER_PROGRESS_MIGRATION_FILE}.bak"

# Find the devise_create_users migration file
DEVISE_USERS_MIGRATION_FILE=$(ls db/migrate/*_devise_create_users.rb | head -n 1)
# Check if is_admin already has default:false from generator, if not add it
if ! grep -q "default: false" "$DEVISE_USERS_MIGRATION_FILE"  || ! grep -q "is_admin" "$DEVISE_USERS_MIGRATION_FILE"; then
    # This attempts to add it if the column exists but lacks the default, or if the column was missed.
    # A more robust way would be a separate migration if `rails g devise User is_admin:boolean:default_false` didn't set it.
    # For now, this is an attempt. The generator should handle `default_false`.
    # Adding null: false as well.
    sed -i.bak '/t.string :language/i \
      # Assuming is_admin was generated; if not, this won'\''t add the column, only modify if t.boolean :is_admin exists\
      # change_column :users, :is_admin, :boolean, default: false, null: false' "$DEVISE_USERS_MIGRATION_FILE"
    # The generator `is_admin:boolean:default_false` should make this unnecessary.
    # We will rely on the generator to correctly set the default in the migration it creates for the User model.
    # The `sed` line for `is_admin` default in the previous script version was:
    # sed -i 's/t.boolean :is_admin/t.boolean :is_admin, default: false/' $(ls db/migrate/*_devise_create_users.rb)
    # This simpler form relies on the generator doing its job. If it generates `t.boolean :is_admin` without default,
    # then manual adjustment or a new migration is cleaner.
    # For this script, we'll assume the generator for Devise field correctly adds the default.
    # If `rails g devise User field:type:default_value` syntax is fully supported and works, this is fine.
    # `default_false` is a bit unusual for the generator syntax, usually it's `default:false` in a migration.
    # Let's assume the migration will be: t.boolean :is_admin
    # And we modify it:
    if grep "t.boolean :is_admin" "$DEVISE_USERS_MIGRATION_FILE"; then
        sed -i.bak 's/t.boolean :is_admin/t.boolean :is_admin, default: false, null: false/' "$DEVISE_USERS_MIGRATION_FILE" && rm "${DEVISE_USERS_MIGRATION_FILE}.bak"
    else
        warn "Could not find 't.boolean :is_admin' in Devise migration to set default. Please check: ${DEVISE_USERS_MIGRATION_FILE}"
    fi
fi


# --- Generate Controllers ---
log "Generating controllers..."
bundle exec rails g controller HomeController index find_game # For landing page and joining a game
bundle exec rails g controller PlayerInterfaceController show play submit_answer # For player gameplay
bundle exec rails g controller Games --skip-routes # For organizers (CRUD for games)
bundle exec rails g controller Clues --parent=Game --skip-routes # For organizers (CRUD for clues, nested)

# --- Configure Routes ---
# (Content of config/routes.rb is the same as before)
log "Configuring routes (config/routes.rb)..."
cat << EOF > config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  get "up" => "rails/health#show", as: :rails_health_check
  root "home#index"

  post "find_game" => "home#find_game", as: :find_game

  scope "/play/:game_public_code", as: :play_game do
    get "/", to: "player_interface#show", as: :start
    post "/submit", to: "player_interface#submit_answer", as: :submit_answer
    get "/clue/:series_id", to: "player_interface#show_clue", as: :clue
    get "/print", to: "player_interface#print_clues", as: :print_clues
  end

  resources :games do
    member do
      get :map_view
      get :player_status
    end
    resources :clues, except: [:index, :show]
  end
  get "dashboard" => "games#index", as: :user_dashboard
end
EOF

# --- Create ricclib/color.rb ---
# (Content of ricclib/color.rb is the same as before)
log "Creating ricclib/color.rb..."
mkdir -p lib/ricclib
cat << EOF > lib/ricclib/color.rb
# lib/ricclib/color.rb
module Ricclib
  module Color
    COLORS = {
      black:   30, red:     31, green:   32, yellow:  33,
      blue:    34, magenta: 35, cyan:    36, white:   37,
      default: 39
    }.freeze

    STYLES = {
      bold:      1,
      underline: 4,
      normal:    0 # Resets all attributes
    }.freeze

    def self.colorize(text, color_name, style_name = nil)
      color_code = COLORS[color_name.to_sym] || COLORS[:default]
      style_code_str = style_name ? "\#{STYLES[style_name.to_sym]};" : ""
      reset_code = STYLES[:normal]
      "\e[\#{style_code_str}\#{color_code}m\#{text}\e[\#{reset_code}m"
    end

    COLORS.each_key do |color_name|
      define_singleton_method(color_name) do |text|
        colorize(text, color_name)
      end
    end

    STYLES.each_key do |style_name|
      next if style_name == :normal
      define_singleton_method(style_name) do |text, color_name = :default|
        colorize(text, color_name, style_name)
      end
    end
  end
end
EOF
# Autoload ricclib
# Check if already added to prevent duplicates if script is re-run on existing structure (not recommended)
if ! grep -q "Rails.autoloaders.main.push_dir(Rails.root.join('lib'))" config/application.rb; then
  echo "" >> config/application.rb # Ensure it's on a new line
  echo "Rails.autoloaders.main.push_dir(Rails.root.join('lib'))" >> config/application.rb
  echo "Rails.autoloaders.main.push_dir(Rails.root.join('lib/ricclib'))" >> config/application.rb # More specific
fi


# --- Create justfile ---
# (Content of justfile is the same as before)
log "Creating justfile..."
cat << EOF > justfile
# justfile for TrHuGa

# Variables
DOCKER_IMAGE_NAME := trhuga-app
DOCKER_TAG := latest
APP_NAME := ${APP_NAME} # Use the app name from the script

# Default command: List available commands
default: list

# List available commands
list:
    @just --list

# Setup the application (bundle, db)
setup:
    @echo "📦 Installing dependencies (if any new ones)..."
    bundle install
    @echo "⚙️ Preparing database..."
    rails db:prepare
    @echo "🌱 Seeding database..."
    rails db:seed
    @echo "✅ Setup complete!"

# Start development server
dev:
    @echo "🚀 Starting development server (./bin/dev)..."
    ./bin/dev

# Run database migrations
db-migrate:
    @echo "Applying database migrations..."
    rails db:migrate

# Seed the database
db-seed:
    @echo "Seeding database..."
    rails db:seed

# Reset database (drop, create, migrate, seed)
db-reset:
    @echo "Resetting database..."
    rails db:reset

# Run tests (RSpec)
test:
    @echo "Running RSpec tests..."
    bundle exec rspec

# Open Rails console
console:
    @echo "Opening Rails console..."
    rails c

# Build Docker image (if you have a Dockerfile)
build-docker:
    @echo "Building Docker image \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}..."
    @echo "Note: This script does not generate a Dockerfile by default for Rails 8."
    @echo "If you have one (e.g., from 'rails new --docker' or manually added), this command attempts to build it."
    if [ -f Dockerfile ]; then \
        docker build . -t \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}; \
    else \
        echo "Dockerfile not found. Skipping build."; \
    fi

# Run Docker container (example, adjust ports and env vars)
run-docker: # build-docker # Make build optional if Dockerfile might not exist
    @echo "Running Docker container \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}..."
    @echo "Note: Ensure your Docker image is built and Dockerfile/container is configured correctly."
    if [ -f Dockerfile ]; then \
        docker run -p 3000:3000 \
            -e RAILS_MASTER_KEY=\$(cat config/master.key) \
            -e DATABASE_URL="postgresql://postgres:password@host.docker.internal:5432/\${APP_NAME}_development" \
            \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}; \
    else \
        echo "Dockerfile not found. Cannot run container. Please ensure you have a Docker setup."; \
    fi


# Lint code (requires RuboCop)
lint:
    @echo "Linting Ruby code with RuboCop..."
    if bundle exec rubocop --version > /dev/null 2>&1; then \
        bundle exec rubocop || echo "RuboCop found issues."; \
    else \
        echo "RuboCop not found in bundle. Skipping lint."; \
    fi

# Auto-correct RuboCop offenses
lint-fix:
    @echo "Auto-correcting RuboCop offenses..."
    if bundle exec rubocop --version > /dev/null 2>&1; then \
        bundle exec rubocop -A || echo "RuboCop auto-correction attempted."; \
    else \
        echo "RuboCop not found in bundle. Skipping lint-fix."; \
    fi
EOF

# --- Create .env.dist ---
# (Content of .env.dist is the same as before)
log "Creating .env.dist..."
cat << EOF > .env.dist
# .env.dist - Sample environment variables for TrHuGa
# Copy this file to .env and fill in your actual values.
# .env is ignored by git by default if you add it to .gitignore.

# Rails master key (get from config/master.key or generate with rails credentials:edit)
# RAILS_MASTER_KEY=your_rails_master_key

# Database URL (PostgreSQL for production/staging, SQLite for dev is also an option via database.yml)
# Example for local PostgreSQL:
# DATABASE_URL="postgresql://YOUR_USER:YOUR_PASSWORD@localhost:5432/${APP_NAME}_development"
# For Cloud SQL (prod):
# DATABASE_URL="postgresql://USER:PASSWORD@CLOUD_SQL_PROXY_HOST:PORT/DATABASE_NAME"

# Gemini API Key
GEMINI_API_KEY="YOUR_GEMINI_API_KEY_HERE"

# Devise Admin User for seeding
ADMIN_EMAIL="palladiusbonton@gmail.com"
ADMIN_PASSWORD="aVerySecurePassword123!" # Change this in your actual .env

# Google Cloud Project (for GCS, Cloud Run, etc.)
# GOOGLE_CLOUD_PROJECT="your-gcp-project-id"
# GCS_BUCKET_NAME="your-trhuga-assets-bucket-name"

# Devise secret key (usually handled by Rails, but can be set if needed)
# DEVISE_SECRET_KEY="your_devise_secret_key_from_devise_initializer"

EOF
if ! grep -q ".env" .gitignore; then
  echo ".env" >> .gitignore
fi


# --- Populate Model Files ---
# (Content of model files User, Game, Clue, PlayerProgress are the same as before)
log "Populating model files (app/models/)..."
# User Model
cat << EOF > app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :games, dependent: :destroy

  VALID_LANGUAGES = %w[en it fr pt de pl ja].freeze
  validates :language, inclusion: { in: VALID_LANGUAGES, message: "%{value} is not a valid language code" }, allow_nil: true

  def admin?
    is_admin
  end

  # Called by Devise. For new records, is_admin is false due to DB default.
  # If you need to set it true for specific cases (like admin creation via console/seed), do it explicitly.
end
EOF

# Game Model
cat << EOF > app/models/game.rb
class Game < ApplicationRecord
  belongs_to :user
  has_many :clues, -> { order(series_id: :asc) }, dependent: :destroy, inverse_of: :game

  enum default_clue_type: { Youtube: 0, physical: 1 }

  validates :name, presence: true
  validates :public_code, presence: true, uniqueness: { case_sensitive: false }, length: { is: 6 }
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date
  validate :clues_series_ids_are_consecutive, if: :clues_changed_for_validation?

  before_validation :generate_public_code, on: :create
  before_save :upcase_public_code

  scope :published, -> { where(published: true) }
  scope :active, -> { published.where("start_date <= :today AND end_date >= :today", today: Time.current) }

  attr_accessor :skip_clue_validation # To allow skipping validation during intermediate steps

  private

  def generate_public_code
    loop do
      self.public_code = SecureRandom.alphanumeric(6).upcase
      break unless Game.exists?(public_code: self.public_code)
    end
  end

  def upcase_public_code
    self.public_code.upcase! if public_code.present?
  end

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?
    if end_date < start_date
      errors.add(:end_date, "must be after the start date")
    end
  end

  def clues_changed_for_validation?
    # Run validation if clues are newly associated, changed, or game is new.
    # Or more simply, if not explicitly skipped.
    return false if @skip_clue_validation
    new_record? || clues.any?(&:new_record?) || clues.any?(&:changed?) || clues.any?(&:marked_for_destruction?)
  end

  def clues_series_ids_are_consecutive
    # This validation runs when the Game object is saved IF clues have changed or it's a new game.
    current_clues = clues.reject(&:marked_for_destruction?)
    return if current_clues.empty?

    sorted_ids = current_clues.map(&:series_id).compact.sort

    is_valid_sequence = sorted_ids.first == 1 && sorted_ids.each_with_index.all? { |id, index| id == index + 1 }

    unless is_valid_sequence
      errors.add(:base, "Clue series_ids must be consecutive starting from 1 (e.g., 1, 2, 3). Found: \#{sorted_ids.join(', ')}")
    end
  end
end
EOF

# Clue Model
cat << EOF > app/models/clue.rb
class Clue < ApplicationRecord
  belongs_to :game

  enum clue_type: { Youtube: 0, physical: 1 }

  validates :series_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :unique_code, presence: true, length: { is: 4 }, uniqueness: { scope: :game_id }
  validates :parent_advisory, presence: true
  validates :clue_type, presence: true

  with_options if: :Youtube? do |qa|
    qa.validates :question, presence: true
    qa.validates :answer, presence: true
  end

  with_options if: :physical? do |p|
    p.validates :next_clue_riddle, presence: true
  end

  before_validation :generate_unique_code, on: :create, if: -> { unique_code.blank? }
  validates :series_id, uniqueness: { scope: :game_id }

  # After save, touch the game to trigger its validations if clues are managed separately.
  # However, the Game's validation `clues_series_ids_are_consecutive` is the primary check point.
  # Consider how to best ensure game validity when clues are modified.
  # One way is to always save clues through the game's nested attributes, or explicitly validate game after clue changes.
  after_commit :touch_game_if_needed, on: [:create, :update, :destroy]


  private

  def generate_unique_code
    loop do
      self.unique_code = format('%04d', SecureRandom.rand(10000))
      break unless game && game.clues.where.not(id: self.id).exists?(unique_code: self.unique_code)
      break if game.nil?
    end
  end

  def touch_game_if_needed
    # This could trigger game validations if game is configured to validate on touch or save.
    # The Game model's clue validation should ideally run when a Game is saved.
    # If clues are manipulated and saved directly, this might be a place to ensure consistency.
    # For now, we rely on saving the Game object to trigger its clue sequence validation.
    # game.touch if game.persisted? # Example if we need to trigger game's updated_at
  end
end
EOF

# PlayerProgress Model
cat << EOF > app/models/player_progress.rb
class PlayerProgress < ApplicationRecord
  belongs_to :game

  serialize :unlocked_clue_series_ids, type: Array, coder: YAML # Or JSON for PG JSONB

  validates :nickname, presence: true
  validates :language, presence: true
  validates :player_token, presence: true, uniqueness: true
  validates :current_clue_series_id, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  before_validation :ensure_player_token, on: :create
  before_validation :initialize_unlocked_clues, on: :create

  def ensure_player_token
    self.player_token ||= SecureRandom.hex(16)
  end

  def initialize_unlocked_clues
    self.unlocked_clue_series_ids ||= [1]
    self.current_clue_series_id ||= 1
  end

  def unlock_clue!(series_id)
    normalized_id = series_id.to_i
    return false if normalized_id <= 0

    self.unlocked_clue_series_ids << normalized_id unless self.unlocked_clue_series_ids.include?(normalized_id)
    self.unlocked_clue_series_ids.sort!.uniq!

    self.current_clue_series_id = [self.current_clue_series_id, normalized_id].max
    save # Consider if this should be save! or handle errors
  end

  def can_access_clue?(series_id)
    self.unlocked_clue_series_ids.include?(series_id.to_i)
  end
end
EOF

# --- Application Controller Setup ---
# (Content of ApplicationController is the same as before)
log "Configuring ApplicationController..."
cat << EOF > app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_locale

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:language])
    devise_parameter_sanitizer.permit(:account_update, keys: [:language])
  end

  def set_locale
    current_player_language = session[:player_language]

    if current_player_language && User::VALID_LANGUAGES.include?(current_player_language)
      I18n.locale = current_player_language
    elsif user_signed_in? && current_user.language.present? && User::VALID_LANGUAGES.include?(current_user.language)
      I18n.locale = current_user.language
    else
      I18n.locale = I18n.default_locale
    end
  end

  def current_game_for_player
    @current_game_for_player ||= Game.active.find_by(public_code: params[:game_public_code]&.upcase)
    unless @current_game_for_player
      redirect_to root_path, alert: "Game not found or not active."
      return nil
    end
    @current_game_for_player
  end

  def current_player_progress(game)
    token = session["player_token_for_game_\#{game.id}"]
    return nil unless token && game
    PlayerProgress.find_by(game_id: game.id, player_token: token)
  end

  def ensure_player_session(game)
    unless current_player_progress(game)
        session[:joining_game_public_code] = game.public_code
        redirect_to root_path,
                    alert: "Please join the game first (enter nickname and choose language)."
        return false
    end
    true
  end
end
EOF

# --- Create PlayerInterfaceController ---
# (Content of PlayerInterfaceController is the same as before)
log "Creating basic PlayerInterfaceController..."
cat << EOF > app/controllers/player_interface_controller.rb
class PlayerInterfaceController < ApplicationController
  before_action :set_game_and_progress_and_locale
  before_action :ensure_player_can_access_requested_clue, only: [:show_clue] # Renamed for clarity

  # GET /play/:game_public_code
  def show
    @clue = @game.clues.find_by(series_id: @player_progress.current_clue_series_id)
    if @clue.nil? && @player_progress.current_clue_series_id > @game.clues.maximum(:series_id).to_i
      flash.now[:notice] = "Congratulations! You've completed the treasure hunt! 🥳"
    elsif @clue.nil?
      flash.now[:alert] = "Error: Current clue not found."
    end
  end

  # POST /play/:game_public_code/submit
  def submit_answer
    submitted_value = params[:answer_or_code].to_s.strip
    current_clue = @game.clues.find_by(series_id: @player_progress.current_clue_series_id)

    unless current_clue
      redirect_to play_game_start_path(@game.public_code), alert: "Could not find current clue."
      return
    end

    if current_clue.Youtube?
      # is_correct = LlmService.validate_answer(current_clue.question, current_clue.answer, submitted_value, @game.context)
      is_correct = submitted_value.downcase == current_clue.answer.downcase # Placeholder
      if is_correct
        proceed_to_next_clue(current_clue)
      else
        flash.now[:alert] = "That's not quite right. Try again! 🤔"
        @clue = current_clue
        render :show, status: :unprocessable_entity
      end
    elsif current_clue.physical?
      found_clue = @game.clues.find_by(unique_code: submitted_value)

      if found_clue && found_clue.series_id == current_clue.series_id + 1
        @player_progress.unlock_clue!(found_clue.series_id)
        flash[:notice] = "Correct code! 🎉 Here's your next challenge!"
        redirect_to play_game_clue_path(@game.public_code, series_id: found_clue.series_id)
      elsif found_clue
        flash.now[:alert] = "That's a valid code, but not for the next clue in this sequence. Keep looking! 🧐"
        @clue = current_clue
        render :show, status: :unprocessable_entity
      else
        flash.now[:alert] = "Hmm, that code doesn't seem right. Double-check it! 🔢"
        @clue = current_clue
        render :show, status: :unprocessable_entity
      end
    end
  end

  # GET /play/:game_public_code/clue/:series_id
  def show_clue
    # @clue is set by ensure_player_can_access_requested_clue
    render :show # Renders the 'show' template with @clue
  end

  # GET /play/:game_public_code/print
  def print_clues
    game_for_print = Game.find_by(public_code: params[:game_public_code]&.upcase) # Separate query, might not need full player session
    unless game_for_print && (current_user && (game_for_print.user == current_user || current_user.admin?))
        redirect_to root_path, alert: "You are not authorized to print these clues."
        return
    end

    @game_for_print = game_for_print # Avoid conflict with @game from player session
    @physical_clues = @game_for_print.clues.where(clue_type: :physical).order(:series_id)

    render plain: "PDF printing for physical clues of game #{@game_for_print.name} - Implement with Prawn."
  end

  private

  def set_game_and_progress_and_locale
    @game = current_game_for_player # From ApplicationController
    return unless @game

    @player_progress = current_player_progress(@game)

    unless @player_progress
      session[:joining_game_public_code] = @game.public_code
      redirect_to root_path, alert: "Please join the game with a nickname and language first!"
      return
    end

    if @player_progress.language.present? && User::VALID_LANGUAGES.include?(@player_progress.language)
      I18n.locale = @player_progress.language
    end
  end

  def ensure_player_can_access_requested_clue
    requested_series_id = params[:series_id].to_i
    unless @player_progress.can_access_clue?(requested_series_id)
      redirect_to play_game_start_path(@game.public_code), alert: "You haven't unlocked that clue yet!"
      return
    end
    @clue = @game.clues.find_by(series_id: requested_series_id)
    unless @clue
      redirect_to play_game_start_path(@game.public_code), alert: "Clue not found."
    end
  end

  def proceed_to_next_clue(solved_clue)
    next_series_id = solved_clue.series_id + 1
    next_clue = @game.clues.find_by(series_id: next_series_id)

    @player_progress.unlock_clue!(solved_clue.series_id)

    if next_clue
      @player_progress.update(current_clue_series_id: next_clue.series_id)
      @player_progress.unlock_clue!(next_clue.series_id)

      flash[:notice] = "Correct! 🎉 Here's the next clue."
      redirect_to play_game_clue_path(@game.public_code, series_id: next_clue.series_id)
    else
      @player_progress.update(current_clue_series_id: next_series_id)
      redirect_to play_game_start_path(@game.public_code), notice: "Woohoo! You've solved all the clues! TREASURE HUNT COMPLETE! 🏆"
    end
  end
end
EOF

# --- Create HomeController ---
# (Content of HomeController is the same as before)
log "Creating basic HomeController..."
cat << EOF > app/controllers/home_controller.rb
class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index, :find_game]

  def index
    @game_code = session.delete(:joining_game_public_code) || params[:game_code]
    # Provide available languages for the dropdown
    @available_languages = User::VALID_LANGUAGES.map { |lang_code| [I18n.t("languages.\#{lang_code}", default: lang_code.upcase), lang_code] }
  end

  def find_game
    public_code = params[:public_code]&.strip&.upcase
    nickname = params[:nickname]&.strip
    language = params[:language]

    game = Game.active.find_by(public_code: public_code)

    if game.nil?
      redirect_to root_path(game_code: public_code), alert: "Oops! Game not found or not currently active. Check the code and try again! 🧐"
      return
    end

    if nickname.blank?
      redirect_to root_path(game_code: public_code), alert: "You need a cool nickname to play! 😎"
      return
    end

    unless User::VALID_LANGUAGES.include?(language)
      redirect_to root_path(game_code: public_code), alert: "Please select a language to play in! 🗣️"
      return
    end

    player_progress = game.player_progresses.create(
      nickname: nickname,
      language: language
    )

    if player_progress.persisted?
      session["player_token_for_game_\#{game.id}"] = player_progress.player_token
      session[:player_language] = player_progress.language
      redirect_to play_game_start_path(game_public_code: game.public_code), notice: "Welcome, \#{nickname}! Let the treasure hunt begin! 🚀"
    else
      # This path should ideally not be taken if validations are simple like presence.
      # If complex validations fail, errors will be here.
      error_messages = player_progress.errors.full_messages.join(', ')
      redirect_to root_path(game_code: public_code), alert: "Could not start the game. \#{error_messages.presence || 'Please try again.'}"
    end
  end
end
EOF

# --- Create GamesController ---
# (Content of GamesController is the same as before)
log "Creating basic GamesController..."
cat << EOF > app/controllers/games_controller.rb
class GamesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game, only: %i[show edit update destroy map_view player_status]
  before_action :authorize_owner_or_admin, only: %i[show edit update destroy map_view player_status]

  def index
    @games = current_user.admin? ? Game.all.order(created_at: :desc) : current_user.games.order(created_at: :desc)
  end

  def show
    @clues = @game.clues.order(:series_id) # Eager load or ensure order
  end

  def new
    @game = current_user.games.build
    @game.default_clue_type ||= :Youtube
  end

  def create
    @game = current_user.games.build(game_params)
    # Clues are not typically created at the same time as the game from this form
    # So skip_clue_validation might not be needed here unless form allows adding initial clues.
    # @game.skip_clue_validation = true # If form adds clues that might not be sequential yet.
    if @game.save
      redirect_to @game, notice: 'Game was successfully created. Time to add some clues! 🕵️'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    # If clues can be reordered/deleted directly on game's edit form, clue validation is important.
    # If clues are managed separately, this is simpler.
    if @game.update(game_params)
      redirect_to @game, notice: 'Game was successfully updated. ✨'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @game.destroy
    redirect_to games_url, notice: 'Game was successfully obliterated. 💣', status: :see_other
  end

  def map_view
    @physical_clues = @game.clues.where(clue_type: :physical).where.not(geo_x: nil, geo_y: nil)
    render plain: "Map view for game '#{@game.name}'. Found #{@physical_clues.count} physical clues with geo data. Implement with Google Maps JS API."
  end

  def player_status
    @player_progresses = @game.player_progresses.order(updated_at: :desc)
    render plain: "Player status for game '#{@game.name}'. #{@player_progresses.count} players. Implement with Turbo Streams."
  end

  private

  def set_game
    # Eager load clues when game is loaded, to help with validation or display
    @game = Game.includes(:clues).find(params[:id])
  end

  def authorize_owner_or_admin
    unless @game.user == current_user || current_user.admin?
      redirect_to games_path, alert: "You are not authorized to perform this action. 🛑"
    end
  end

  def game_params
    params.require(:game).permit(:name, :start_date, :end_date, :published, :default_clue_type, :context)
  end
end
EOF

# --- Create CluesController ---
# (Content of CluesController is the same as before, with minor note)
log "Creating basic CluesController..."
cat << EOF > app/controllers/clues_controller.rb
class CluesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :set_clue, only: %i[edit update destroy]
  before_action :authorize_owner_or_admin_for_game

  def new
    @clue = @game.clues.build
    @clue.clue_type = @game.default_clue_type
    max_series_id = @game.clues.maximum(:series_id) || 0
    @clue.series_id = max_series_id + 1
  end

  def create
    @clue = @game.clues.build(clue_params)
    if @clue.save
      # Game validation of clue sequence will occur when Game is next saved,
      # or if we explicitly validate and save the game here.
      # For simplicity, we assume admin ensures sequence or game edit re-validates.
      redirect_to game_path(@game, anchor: "clue-#{@clue.id}"), notice: 'Clue was successfully added! 💡'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @clue.update(clue_params)
      redirect_to game_path(@game, anchor: "clue-#{@clue.id}"), notice: 'Clue was successfully updated. 👍'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @clue.destroy
    redirect_to game_path(@game), notice: 'Clue was successfully deleted. 💨', status: :see_other
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_clue
    @clue = @game.clues.find(params[:id])
  end

  def authorize_owner_or_admin_for_game
    unless @game.user == current_user || current_user.admin?
      redirect_to games_path, alert: "You are not authorized to manage clues for this game. 🚫"
    end
  end

  def clue_params
    params.require(:clue).permit(
      :series_id, :unique_code, :parent_advisory, :published, :clue_type,
      :question, :answer, :visual_description,
      :next_clue_riddle, :location, :geo_x, :geo_y, :location_addon
    )
  end
end
EOF

# --- Locales for languages ---
# (Content of en.yml is the same as before)
log "Adding basic locale structure for languages..."
mkdir -p config/locales
cat << EOF > config/locales/en.yml
en:
  hello: "Hello world"
  languages:
    en: "English"
    it: "Italian"
    fr: "French"
    pt: "Portuguese"
    de: "German"
    pl: "Polish"
    ja: "Japanese"
  game:
    find_game: "Find Game"
    enter_code: "Enter Game Code (e.g., R7M5CH)"
    nickname: "Your Nickname"
    select_language: "Select Language"
    start_hunt: "Start Hunt!"
  clue:
    submit_answer: "Submit Answer"
    submit_code: "Enter Code Found"
    your_answer_or_code: "Your Answer or Code"
EOF

# --- Database Seeds ---
# (Content of db/seeds.rb is the same as before, including module User/Game/Clue extension for newly_created?)
# Small modification to the ActiveRecord::Base extension for newly_created? to avoid potential conflicts
# if the script is run multiple times or if such a method already exists.
log "Populating db/seeds.rb..."
cat << EOF > db/seeds.rb
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require 'ricclib/color' # For colorful seed output

puts Ricclib::Color.yellow("Seeding database for TrHuGa... 🌱")

# Helper for seeds to track if a record was newly created by find_or_create_by!
module SeedHelper
  def self.find_or_create_with_status!(model, attributes, &block)
    record = model.find_by(attributes.slice(model.primary_key.to_sym) # Use primary key for lookup if suitable
                           .merge(attributes.slice(*model.columns.map(&:name).map(&:to_sym).select { |col| model.unique_constraints_on(col) }))) # Or unique constraints

    # Fallback to a common unique field if primary key is not in attributes, e.g. email for User, public_code for Game
    if !record && model == User
        record = model.find_by(email: attributes[:email])
    elsif !record && model == Game
        record = model.find_by(public_code: attributes[:public_code])
    elsif !record && model == Clue # Clues need game_id and series_id or unique_code
        record = model.find_by(game_id: attributes[:game].id, series_id: attributes[:series_id]) if attributes[:game] && attributes[:series_id]
    end


    was_new = false
    unless record
      record = model.new(attributes)
      block.call(record) if block
      record.save! # save! will raise error if fails
      was_new = true
    end
    [record, was_new]
  end
end


# === Admin User ===
admin_email_env = ENV.fetch('ADMIN_EMAIL', 'palladiusbonton@gmail.com')
admin_password_env = ENV.fetch('ADMIN_PASSWORD', 'aVerySecurePassword123!')

puts Ricclib::Color.blue("Creating admin user...")
admin_user, admin_newly_created = SeedHelper.find_or_create_with_status!(User, { email: admin_email_env }) do |user|
  user.password = admin_password_env
  user.password_confirmation = admin_password_env
  user.is_admin = true
  user.language = 'en'
end

if admin_user.persisted?
  puts Ricclib::Color.green("Admin user '#{admin_user.email}' #{admin_newly_created ? 'created' : 'found'}.")
else
  puts Ricclib::Color.red("Failed to ensure admin user: #{admin_user.errors.full_messages.join(', ')}")
end

# === Sample Game 1: Q&A - "Riddles in the Digital Park" ===
puts Ricclib::Color.blue("Creating Sample Q&A Game...")
game1, game1_newly_created = SeedHelper.find_or_create_with_status!(Game, { public_code: "RIDL01", user: admin_user }) do |g|
  g.name = "Riddles in the Digital Park"
  g.start_date = Time.current - 1.day
  g.end_date = Time.current + 30.days
  g.published = true
  g.default_clue_type = :Youtube
  g.context = "A fun riddle game for kids aged 6-10. Focus on animals and nature."
end

if game1.persisted?
  puts Ricclib::Color.green("Game '#{game1.name}' #{game1_newly_created ? 'created' : 'found'}.")

  clue1_attrs = { game: game1, series_id: 1, clue_type: :Youtube, question: "I have a trunk, but I'm not a car. I have big ears, but can't hear you from far. What am I?", answer: "Elephant", parent_advisory: "First clue, displayed automatically.", visual_description: "A friendly cartoon elephant waving its trunk." }
  SeedHelper.find_or_create_with_status!(Clue, clue1_attrs)

  clue2_attrs = { game: game1, series_id: 2, clue_type: :Youtube, question: "I have stripes, but I'm not a zebra. I live in the jungle and say 'Roar!'. What am I?", answer: "Tiger", parent_advisory: "Revealed after answering Clue 1 correctly.", visual_description: "A majestic tiger with orange and black stripes." }
  SeedHelper.find_or_create_with_status!(Clue, clue2_attrs)

  clue3_attrs = { game: game1, series_id: 3, clue_type: :Youtube, question: "I can fly, but I have no wings. I cry, but I have no eyes. What am I?", answer: "Cloud", parent_advisory: "Revealed after answering Clue 2 correctly.", visual_description: "A fluffy white cloud in a blue sky." }
  SeedHelper.find_or_create_with_status!(Clue, clue3_attrs)

  game1.skip_clue_validation = false # Ensure validation runs
  unless game1.save # This will trigger validations including clue sequence.
    puts Ricclib::Color.red("Warning: Game '#{game1.name}' has validation errors after adding clues: #{game1.errors.full_messages.join(', ')}")
  end
else
  puts Ricclib::Color.red("Failed to create Game 1: #{game1.errors.full_messages.join(', ')}")
end


# === Sample Game 2: Physical - "Zürich Lakeside Adventure" ===
puts Ricclib::Color.blue("Creating Sample Physical Game in Zürich...")
game2, game2_newly_created = SeedHelper.find_or_create_with_status!(Game, { public_code: "ZURI01", user: admin_user }) do |g|
  g.name = "Zürich Lakeside Adventure"
  g.start_date = Time.current - 1.day
  g.end_date = Time.current + 30.days
  g.published = true
  g.default_clue_type = :physical
  g.context = "A physical treasure hunt around Lake Zürich for kids aged 8-12. Encourages observation and light walking."
end

if game2.persisted?
  puts Ricclib::Color.green("Game '#{game2.name}' #{game2_newly_created ? 'created' : 'found'}.")

  SeedHelper.find_or_create_with_status!(Clue, { game: game2, series_id: 1, clue_type: :physical, parent_advisory: "Start at Bürkliplatz. Give this first clue to the kids directly.", next_clue_riddle: "Where flowers bloom and boats set sail, find the big clock that tells a tale. (Hint: Near the lake ferry terminal)", location: "Bürkliplatz, Zürich, Switzerland", geo_x: 8.5409, geo_y: 47.3653, location_addon: "Near the main flowerbed facing the lake."})
  SeedHelper.find_or_create_with_status!(Clue, { game: game2, series_id: 2, clue_type: :physical, parent_advisory: "Hide this clue near the ZSG Ferry Terminal clock at Bürkliplatz.", next_clue_riddle: "I guard the entrance to an old church, with two tall towers. Lions watch nearby. What am I? (Hint: A famous Münster)", location: "ZSG Bürkliplatz (See), Zürich, Switzerland", geo_x: 8.5415, geo_y: 47.3660, location_addon: "Tucked under the information board by the large clock."})
  SeedHelper.find_or_create_with_status!(Clue, { game: game2, series_id: 3, clue_type: :physical, parent_advisory: "Hide this clue at the main entrance of Grossmünster, perhaps near one of the lion statues if safe and permitted.", next_clue_riddle: "Cross the river on a bridge named after a vegetable, and find a toy store with a giant bear! The final treasure is there!", location: "Grossmünster, Zwinglipl. 7, 8001 Zürich, Switzerland", geo_x: 8.543, geo_y: 47.369, location_addon: "At the base of the northernmost lion statue (if applicable and safe) or a nearby bench."})
  SeedHelper.find_or_create_with_status!(Clue, { game: game2, series_id: 4, clue_type: :physical, parent_advisory: "This is the final treasure location. Place the 'treasure' (e.g. small gifts, cake) at Franz Carl Weber toy store on Bahnhofstrasse after crossing Gemüsebrücke (Rathausbrücke).", next_clue_riddle: "Congratulations! You found the final spot! Look for your 'TREASURE' nearby, perhaps guarded by a friendly store employee or hidden by your game master!", location: "Franz Carl Weber, Bahnhofstrasse 62, 8001 Zürich, Switzerland", geo_x: 8.5390, geo_y: 47.3721, location_addon: "Inside or just outside Franz Carl Weber. The 'treasure' should be waiting!"})

  game2.skip_clue_validation = false
  unless game2.save
    puts Ricclib::Color.red("Warning: Game '#{game2.name}' has validation errors after adding clues: #{game2.errors.full_messages.join(', ')}")
  end
else
  puts Ricclib::Color.red("Failed to create Game 2: #{game2.errors.full_messages.join(', ')}")
end

# Ensure all clues get unique codes if they were just created and model callback didn't fire as expected in seed context
[game1, game2].compact.each do |game|
  next unless game.persisted?
  game.clues.where(unique_code: nil).find_each do |clue|
    clue.send(:generate_unique_code) # Call private method for seeding
    unless clue.save(validate: false) # Save without re-running all validations if just setting code
        puts Ricclib::Color.red("Failed to save clue #{clue.id} for game #{game.name} after generating unique code: #{clue.errors.full_messages.join(', ')}")
    end
  end
  # Re-validate and save the game to check clue sequence integrity.
  game.skip_clue_validation = false
  unless game.valid?
    puts Ricclib::Color.red("Game '#{game.name}' is invalid after seeding clues: #{game.errors.full_messages.join(', ')}")
  else
    # game.save # Re-save if needed, but valid? is the check here.
    puts Ricclib::Color.green("Game '#{game.name}' and its clues seeded successfully and validated.")
  end
end

puts Ricclib::Color.yellow("Seeding finished! 🎉")
EOF


# --- Final Steps ---
log "Running bundle exec rails db:prepare to create DB and load schema (if not exists)..."
bundle exec rails db:prepare

log "Running bundle exec rails db:seed..."
bundle exec rails db:seed

# --- RSpec Setup (if added) ---
if bundle show rspec-rails > /dev/null 2>&1; then
    log "Setting up RSpec..."
    bundle exec rails generate rspec:install
fi


# --- Git Init ---
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  log "Initializing Git repository..."
  git init -b main
  git add .
  git commit -m "🎉 Initial project structure for TrHuGa by sbrodola.sh (v2)"
  log "Git repository initialized and initial commit made."
else
  warn "Git repository already initialized. Skipping git init."
  # Optionally, add and commit any changes made by the script if run on existing repo
  # git add .
  # git commit -m "Applied sbrodola.sh updates"
fi


log "TrHuGa Rails App Generation Complete! 🥳"
info "Next steps:"
info "1. cd ${APP_NAME} (if not already there)"
info "2. Review all generated files, especially models, controllers, and routes."
info "3. Update '.env.dist' to '.env' and fill in your actual API keys and secrets."
info "4. Customize Devise views if needed: rails g devise:views"
info "5. Start developing your views and implementing the LLM logic, Maps API, etc."
info "6. Run 'just dev' or './bin/dev' to start the development server."
echo ""
echo "${bold}${blue}May your code be bug-free and your treasures plentiful! 🗺️💎${normal}"
