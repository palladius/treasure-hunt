#!/bin/bash
# sbrodola.sh - Generates the TrHuGa Rails application

# Stop at the first big error - a treasure hunter's motto!
set -euo pipefail

#APP_NAME="trhuga"
APP_NAME="treasure-hunt-game" # Specify your app name
RUBY_VERSION="3.4.4" # Specify your target Ruby version
#RAILS_VERSION="~> 8.0.0" # Specify your target Rails version
RAILS_VERSION="~> 8.0.2" # Specify your target Rails version

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
    warn "Rails command could not be found. Please install Rails ${RAILS_VERSION} and Ruby ${RUBY_VERSION}."
    exit 1
fi

log "Starting TrHuGa Rails App Generation..."

# --- Create Rails App ---
info "Generating new Rails app: ${APP_NAME}"
rails new "${APP_NAME}" --database=postgresql --css=tailwind --javascript=importmap -T # -T skips Test::Unit files

# --- Navigate into App Directory ---
cd "${APP_NAME}"
log "Changed directory to $(pwd)"

# --- Set Ruby Version ---
info "Setting Ruby version to ${RUBY_VERSION}"
echo "${RUBY_VERSION}" > .ruby-version

# --- Update Gemfile ---
log "Updating Gemfile..."
cat << EOF > Gemfile
source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/\#{repo}.git" }

ruby "${RUBY_VERSION}"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "${RAILS_VERSION}"

# Use pg for PostgreSQL
gem "pg", "~> 1.1"

# Use Puma as the app server
gem "puma", "~> 6.0"

# Use SCSS for stylesheets
# Not strictly needed if Tailwind is primary, but good to have if some SASS is used.
# gem "sassc-rails" # Commented out as Tailwind is the focus

# Transpile JavaScript from ES6 to ES5 with Babel
# gem "babel-transpiler" # Not needed with importmaps usually

# Build JSON APIs with Jbuilder
gem "jbuilder", "~> 2.0"

# Use Redis caching in production
# gem "redis", "~> 4.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]

# Reduces memory usage in development
gem "bootsnap", require: false, group: :development

# Debugging tools
group :development, :test do
  gem "debug", "~> 1.0"
  gem "rspec-rails", "~> 6.0" # Or your preferred testing framework
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  # Use console on exceptions pages
  gem "web-console"
  # Add speed badges [https://github.com/noelrappin/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Hotwire/Turbo
  gem "turbo-rails"
  gem "stimulus-rails"

  # Dotenv for .env file management
  gem "dotenv-rails"
end

# Hotwire/Turbo (already included with new Rails, but ensure it's there)
gem "turbo-rails"
gem "stimulus-rails" # If you plan to use Stimulus controllers

# Active Storage for file uploads
# gem "google-cloud-storage", "~> 1.10", require: false # For GCS, add when ready

# Tailwind CSS
gem "tailwindcss-rails"

# Devise for authentication
gem "devise", "~> 4.9"

# For LLM interaction (Gemini)
# Choose one: direct HTTP or Google Cloud specific gem
gem "google-apis-gemini_v1beta" # More direct for Gemini
# or gem "google-cloud-ai_platform", ">= 0.7" # Broader AI Platform access
gem "http" # A simple HTTP client, or use Faraday

# For PDF Generation
gem "prawn"
gem "prawn-table" # if you need tables in PDF

# For easier .env file handling in development/test
gem "dotenv-rails", groups: [:development, :test]

EOF

# --- Bundle Install ---
log "Running bundle install..."
bundle install

# --- Install Tailwind CSS ---
log "Setting up Tailwind CSS..."
rails tailwindcss:install # This should create necessary files

# --- Devise Setup ---
log "Setting up Devise..."
bundle exec rails g devise:install

info "Creating User model with Devise..."
bundle exec rails g devise User is_admin:boolean:default_false language:string
# Add default for is_admin in migration if generator doesn't
# Add default for language if needed, or handle in model/controller

# --- Generate Models ---
log "Generating models..."

info "Generating Game model..."
bundle exec rails g model Game name:string public_code:string:uniq start_date:datetime end_date:datetime published:boolean default_clue_type:integer context:text user:references
# Add default for published in migration: t.boolean :published, default: true

info "Generating Clue model..."
bundle exec rails g model Clue series_id:integer unique_code:string parent_advisory:text published:boolean clue_type:integer question:string answer:string visual_description:string next_clue_riddle:text location:string geo_x:float geo_y:float location_addon:string game:references
# Add default for published in migration: t.boolean :published, default: true

info "Generating PlayerProgress model..."
bundle exec rails g model PlayerProgress game:references nickname:string language:string current_clue_series_id:integer unlocked_clue_series_ids:text player_token:string:uniq
# Add default for current_clue_series_id in migration: t.integer :current_clue_series_id, default: 1

# --- Add Indexes ---
log "Adding custom indexes to migrations..."
# Find the create_games migration file
GAME_MIGRATION_FILE=$(ls db/migrate/*_create_games.rb)
sed -i "/t.string :public_code/a \ \ \ \ add_index :games, :public_code, unique: true" "$GAME_MIGRATION_FILE"

# Find the create_clues migration file
CLUE_MIGRATION_FILE=$(ls db/migrate/*_create_clues.rb)
sed -i "/t.references :game, null: false, foreign_key: true/a \ \ \ \ add_index :clues, [:game_id, :unique_code], unique: true\n \ \ \ \ add_index :clues, [:game_id, :series_id], unique: true" "$CLUE_MIGRATION_FILE"

# Find the create_player_progresses migration file
PLAYER_PROGRESS_MIGRATION_FILE=$(ls db/migrate/*_create_player_progresses.rb)
sed -i "/t.string :player_token/a \ \ \ \ add_index :player_progresses, :player_token, unique: true" "$PLAYER_PROGRESS_MIGRATION_FILE"

# Update boolean defaults in migrations
sed -i 's/t.boolean :published/t.boolean :published, default: true/' $GAME_MIGRATION_FILE
sed -i 's/t.boolean :published/t.boolean :published, default: true/' $CLUE_MIGRATION_FILE
sed -i 's/t.boolean :is_admin/t.boolean :is_admin, default: false/' $(ls db/migrate/*_devise_create_users.rb)
sed -i 's/t.integer :current_clue_series_id/t.integer :current_clue_series_id, default: 1/' $PLAYER_PROGRESS_MIGRATION_FILE


# --- Generate Controllers ---
log "Generating controllers..."
bundle exec rails g controller HomeController index find_game # For landing page and joining a game
bundle exec rails g controller PlayerInterfaceController show play submit_answer # For player gameplay
bundle exec rails g controller Games --skip-routes # For organizers (CRUD for games)
bundle exec rails g controller Clues --parent=Game --skip-routes # For organizers (CRUD for clues, nested)
# Namespace admin controllers later if needed, e.g., Admin::GamesController

# --- Configure Routes ---
log "Configuring routes (config/routes.rb)..."
cat << EOF > config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

  # Route for players to find and join a game by public_code
  post "find_game" => "home#find_game", as: :find_game

  # Player gameplay routes
  # These routes will likely be under a game's scope, using the public_code or a session
  scope "/play/:game_public_code", as: :play_game do
    get "/", to: "player_interface#show", as: :start
    post "/submit", to: "player_interface#submit_answer", as: :submit_answer
    get "/clue/:series_id", to: "player_interface#show_clue", as: :clue # Allow navigation to unlocked clues
    # PDF download route
    get "/print", to: "player_interface#print_clues", as: :print_clues
  end

  # Organizer/Admin routes for managing games and clues
  resources :games do
    member do
      get :map_view # For Google Maps view of clues
      get :player_status # For real-time player progress
    end
    resources :clues, except: [:index, :show] # Clues managed within a game context
  end

  # A simple dashboard or profile for logged-in users (organizers)
  get "dashboard" => "games#index", as: :user_dashboard

  # Potentially an admin namespace for user management etc.
  # namespace :admin do
  #   resources :users
  # end
end
EOF

# --- Create ricclib/color.rb ---
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
      # Ensure reset happens correctly
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

    def self.test
      puts "Testing Ricclib::Color:"
      COLORS.each_key do |color|
        print send(color, color.to_s.ljust(10))
      end
      puts "\n" + ("-"*20)
      STYLES.each_key do |style|
        next if style == :normal
        print send(style, style.to_s.ljust(10), :cyan)
      end
      puts "\n" + ("-"*20)
      puts bold(red("Bold Red")) + " " + underline(blue("Underline Blue"))
      puts "Test complete."
    end
  end
end
EOF
# Autoload ricclib
echo "Rails.autoloaders.main.push_dir(Rails.root.join('lib'))" >> config/application.rb


# --- Create justfile ---
log "Creating justfile..."
cat << EOF > justfile
# justfile for TrHuGa

# Variables
DOCKER_IMAGE_NAME := trhuga-app
DOCKER_TAG := latest

# Default command: List available commands
default: list

# List available commands
list:
    @just --list

# Setup the application (bundle, yarn, db)
setup:
    @echo "📦 Installing dependencies..."
    bundle install
    # yarn install # If you add JS packages via yarn
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

# Run tests (configure your test suite first)
test:
    @echo "Running tests..."
    bundle exec rspec # Or 'rails test' if using Minitest

# Open Rails console
console:
    @echo "Opening Rails console..."
    rails c

# Build Docker image
build-docker:
    @echo "Building Docker image \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}..."
    docker build . -t \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}

# Run Docker container (example, adjust ports and env vars)
run-docker: build-docker
    @echo "Running Docker container \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}..."
    docker run -p 3000:3000 \
        -e RAILS_MASTER_KEY=\$(cat config/master.key) \
        -e DATABASE_URL="postgresql://postgres:password@host.docker.internal:5432/\${APP_NAME}_development" \
        # Add other ENV VARS as needed
        \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}

# Lint code (requires RuboCop)
lint:
    @echo "Linting Ruby code with RuboCop..."
    bundle exec rubocop || echo "RuboCop found issues."

# Auto-correct RuboCop offenses
lint-fix:
    @echo "Auto-correcting RuboCop offenses..."
    bundle exec rubocop -A || echo "RuboCop auto-correction attempted."

EOF

# --- Create .env.dist ---
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
echo ".env" >> .gitignore

# --- Create Dockerfile ---
log "Creating Dockerfile..."
cat << EOF > Dockerfile
# Dockerfile for TrHuGa Rails App

# Use the official Ruby image that matches your .ruby-version.
# Check https://hub.docker.com/_/ruby for available tags.
ARG RUBY_VERSION=${RUBY_VERSION}
FROM ruby:\$RUBY_VERSION-slim

ARG APP_NAME=${APP_NAME}
ENV RAILS_ENV=production \
    APP_HOME=/usr/src/\$APP_NAME \
    LANG=C.UTF-8 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_JOBS=4

# Install dependencies:
# - build-essential: for native extensions
# - libpq-dev: for pg gem
# - git: for fetching gems from git
# - nodejs & yarn: for asset pipeline if not using importmaps exclusively or for tailwind build
# - tini: for proper signal handling and zombie reaping
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    git \
    curl \
    nodejs npm \
    # tini \ # Useful for an init process
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install a newer version of yarn if needed
# RUN npm install -g yarn

WORKDIR \$APP_HOME

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle install

# Copy the rest of the application code
COPY . .

# Asset precompilation (if needed, Tailwind might handle CSS differently)
# RUN bundle exec rails assets:precompile # For Sprockets. TailwindCSS gem might handle this.

# Expose port 3000 (Puma default)
EXPOSE 3000

# Entrypoint prepares the database.
# CMD ["./bin/docker-entrypoint.sh"] # You would create this script for db:prepare, etc.

# Start Puma server
# Using tini as PID 1
# CMD ["tini", "--", "bundle", "exec", "puma", "-C", "config/puma.rb"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

EOF

# --- Populate Model Files ---
log "Populating model files (app/models/)..."

# User Model
cat << EOF > app/models/user.rb
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :games, dependent: :destroy

  # Validate language (2-letter code)
  # You can expand this list or use a gem for language codes
  VALID_LANGUAGES = %w[en it fr pt de pl ja].freeze
  validates :language, inclusion: { in: VALID_LANGUAGES, message: "%{value} is not a valid language code" }, allow_nil: true

  def admin?
    is_admin
  end
end
EOF

# Game Model
cat << EOF > app/models/game.rb
class Game < ApplicationRecord
  belongs_to :user
  has_many :clues, dependent: :destroy, inverse_of: :game

  # Using Rails enum for default_clue_type
  # 0: QuestionAnswer, 1: Physical
  enum default_clue_type: { Youtube: 0, physical: 1 }

  validates :name, presence: true
  validates :public_code, presence: true, uniqueness: { case_sensitive: false }, length: { is: 6 }
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date
  validate :clues_series_ids_are_consecutive

  before_validation :generate_public_code, on: :create
  before_save :upcase_public_code

  scope :published, -> { where(published: true) }
  scope :active, -> { published.where("start_date <= :today AND end_date >= :today", today: Time.current) }

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

  def clues_series_ids_are_consecutive
    # This validation runs when the Game object is saved.
    # Consider if this should also be enforced more actively when clues are added/removed.
    # For now, it checks the current set of associated clues.
    return if clues.empty? # Or if clues.length == 1 and clues.first.series_id == 1

    # Eager load series_ids to avoid N+1 if clues are not loaded
    # Use .to_a to ensure any pending additions/deletions in memory are considered
    current_clues = clues.reject(&:marked_for_destruction?)
    return if current_clues.empty?

    sorted_ids = current_clues.map(&:series_id).compact.sort

    # Check if starts with 1 and is consecutive
    # e.g. [1,2,3] is good. [1,2,4] is bad. [2,3,4] is bad.
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

  # Using Rails enum for clue_type
  # 0: QuestionAnswer, 1: Physical
  enum clue_type: { Youtube: 0, physical: 1 }

  validates :series_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
  # unique_code should be unique within the scope of a game
  validates :unique_code, presence: true, length: { is: 4 }, uniqueness: { scope: :game_id }
  validates :parent_advisory, presence: true
  validates :clue_type, presence: true

  # Validations for QuestionAnswer type
  with_options if: :Youtube? do |qa|
    qa.validates :question, presence: true
    qa.validates :answer, presence: true
  end

  # Validations for Physical type
  with_options if: :physical? do |p|
    p.validates :next_clue_riddle, presence: true
    # Location can be optional if geo_x/geo_y are primary, or vice-versa
    # p.validates :location, presence: true
    # p.validates :geo_x, presence: true, numericality: true
    # p.validates :geo_y, presence: true, numericality: true
  end

  before_validation :generate_unique_code, on: :create, if: -> { unique_code.blank? }

  # Ensure series_id is unique within the game
  validates :series_id, uniqueness: { scope: :game_id }

  private

  def generate_unique_code
    loop do
      # Generate a 4-digit code (0000-9999)
      self.unique_code = format('%04d', SecureRandom.rand(10000))
      # Check uniqueness within the game this clue belongs to (or will belong to)
      # This requires 'game' association to be set before validation, or handle if game_id is nil.
      # If game is not yet set (e.g. new clue in a new game form), this might be tricky.
      # Typically, clues are created for an existing game.
      break unless game && game.clues.where.not(id: self.id).exists?(unique_code: self.unique_code)
      break if game.nil? # Allow if game is not yet associated, controller should handle assignment
    end
  end
end
EOF

# PlayerProgress Model
cat << EOF > app/models/player_progress.rb
class PlayerProgress < ApplicationRecord
  belongs_to :game

  serialize :unlocked_clue_series_ids, Array # Or JSON if using PostgreSQL JSONB type

  validates :nickname, presence: true
  validates :language, presence: true # Consider validation list like in User model
  validates :player_token, presence: true, uniqueness: true
  validates :current_clue_series_id, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  before_validation :ensure_player_token, on: :create
  before_validation :initialize_unlocked_clues, on: :create

  def ensure_player_token
    self.player_token ||= SecureRandom.hex(16)
  end

  def initialize_unlocked_clues
    # When a player starts, only the first clue (series_id 1) is unlocked.
    self.unlocked_clue_series_ids ||= [1]
    self.current_clue_series_id ||= 1
  end

  def unlock_clue!(series_id)
    normalized_id = series_id.to_i
    return false if normalized_id <= 0 # Invalid series_id

    # Add to unlocked_clue_series_ids if not already present
    self.unlocked_clue_series_ids << normalized_id unless self.unlocked_clue_series_ids.include?(normalized_id)
    self.unlocked_clue_series_ids.sort!.uniq! # Keep it sorted and unique

    # Update current_clue_series_id if this is a new highest
    self.current_clue_series_id = [self.current_clue_series_id, normalized_id].max
    save
  end

  def can_access_clue?(series_id)
    self.unlocked_clue_series_ids.include?(series_id.to_i)
  end

end
EOF


# --- Application Controller Setup ---
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
    # Player language preference could be stored in session or PlayerProgress model
    # For now, an example:
    # params[:locale] || session[:locale] || I18n.default_locale
    # For TrHuga, player's language is key. Organizers use their User.language

    current_player_language = session[:player_language] # Set this when player joins game

    if current_player_language && User::VALID_LANGUAGES.include?(current_player_language)
      I18n.locale = current_player_language
    elsif user_signed_in? && current_user.language.present? && User::VALID_LANGUAGES.include?(current_user.language)
      I18n.locale = current_user.language
    else
      I18n.locale = I18n.default_locale
    end
  end

  # Helper to find current game for player interface, ensuring it's active
  def current_game_for_player
    @current_game_for_player ||= Game.active.find_by(public_code: params[:game_public_code]&.upcase)
    unless @current_game_for_player
      redirect_to root_path, alert: "Game not found or not active."
      return nil
    end
    @current_game_for_player
  end

  # Helper to get or initialize player progress
  # This would be more robustly handled in a PlayerSessionsController or similar
  def current_player_progress(game)
    token = session["player_token_for_game_\#{game.id}"]
    return nil unless token
    PlayerProgress.find_by(game: game, player_token: token)
  end

  def ensure_player_session(game)
    # Placeholder for logic that ensures a player has "joined" the game
    # (i.e., has a PlayerProgress record and a token in their session)
    # This might involve redirecting to a "join game" screen if no session exists.
    unless current_player_progress(game)
        # Example: Store intended game and redirect to a join page
        session[:joining_game_public_code] = game.public_code
        redirect_to root_path, # or a dedicated join page
                    alert: "Please join the game first (enter nickname and choose language)."
        return false
    end
    true
  end

end
EOF

# --- Create PlayerInterfaceController ---
log "Creating basic PlayerInterfaceController..."
cat << EOF > app/controllers/player_interface_controller.rb
class PlayerInterfaceController < ApplicationController
  before_action :set_game_and_progress, except: [:print_clues] # print_clues might need different auth
  before_action :ensure_player_can_access_current_clue, only: [:show]

  # GET /play/:game_public_code
  def show
    @clue = @game.clues.find_by(series_id: @player_progress.current_clue_series_id)
    if @clue.nil? && @player_progress.current_clue_series_id > @game.clues.maximum(:series_id).to_i
      # Game completed
      flash.now[:notice] = "Congratulations! You've completed the treasure hunt! 🥳"
      # Render a completion page or redirect
    elsif @clue.nil?
      flash.now[:alert] = "Error: Current clue not found."
      # Potentially redirect or render an error state
    end
    # Prepare @next_clue_series_id for navigation if needed
    # The view will show @clue's content (question or riddle)
  end

  # POST /play/:game_public_code/submit
  def submit_answer
    # This action handles both Q&A answers and physical clue codes
    submitted_value = params[:answer_or_code].to_s.strip
    current_clue = @game.clues.find_by(series_id: @player_progress.current_clue_series_id)

    unless current_clue
      redirect_to play_game_start_path(@game.public_code), alert: "Could not find current clue."
      return
    end

    is_correct = false

    if current_clue.Youtube?
      # LLM validation for Q&A
      # This is a placeholder for actual LLM call
      # is_correct = LlmService.validate_answer(current_clue.question, current_clue.answer, submitted_value, @game.context)
      is_correct = submitted_value.downcase == current_clue.answer.downcase # Simple exact match for now
      if is_correct
        proceed_to_next_clue(current_clue)
      else
        flash.now[:alert] = "That's not quite right. Try again! 🤔"
        @clue = current_clue # Re-render current clue
        render :show, status: :unprocessable_entity
      end
    elsif current_clue.physical?
      # Player submits the unique_code of the *next* clue they found physically
      # So, if they are on clue N (seeing riddle for N+1), they find N+1,
      # and submit N+1's unique_code.
      # This submitted_value is the unique_code of the clue they just *found*.
      found_clue = @game.clues.find_by(unique_code: submitted_value)

      if found_clue && found_clue.series_id == current_clue.series_id + 1
        is_correct = true
        # The 'found_clue' is the one they just unlocked.
        # So, their progress moves to 'found_clue.series_id'
        @player_progress.unlock_clue!(found_clue.series_id)
        flash[:notice] = "Correct code! 🎉 Here's your next challenge!"
        redirect_to play_game_clue_path(@game.public_code, series_id: found_clue.series_id)
      elsif found_clue # Code is valid for *a* clue, but not the *next* one in sequence
        flash.now[:alert] = "That's a valid code, but not for the next clue in this sequence. Keep looking! 🧐"
        @clue = current_clue # Re-render current clue's riddle
        render :show, status: :unprocessable_entity
      else
        flash.now[:alert] = "Hmm, that code doesn't seem right. Double-check it! 🔢"
        @clue = current_clue # Re-render current clue's riddle
        render :show, status: :unprocessable_entity
      end
    end
  end

  # GET /play/:game_public_code/clue/:series_id
  def show_clue
    @clue_to_show_series_id = params[:series_id].to_i
    unless @player_progress.can_access_clue?(@clue_to_show_series_id)
      redirect_to play_game_start_path(@game.public_code), alert: "You haven't unlocked that clue yet!"
      return
    end
    @clue = @game.clues.find_by(series_id: @clue_to_show_series_id)
    unless @clue
      redirect_to play_game_start_path(@game.public_code), alert: "Clue not found."
      return
    end
    # This renders the 'show' template with the specific @clue
    render :show
  end

  # GET /play/:game_public_code/print
  def print_clues
    # Note: This action needs to be secured so only appropriate users (e.g., game owner or admin)
    # can print all clues, or it should only print clues relevant to a player if they need it.
    # For now, let's assume it's for the organizer.
    # For organizers, they'd access this through a game management interface.
    # If for players, it should be limited.

    @game = Game.find_by(public_code: params[:game_public_code]&.upcase)
    unless @game && (@game.user == current_user || current_user&.admin?) # Example authorization
        redirect_to root_path, alert: "You are not authorized to print these clues."
        return
    end

    @physical_clues = @game.clues.where(clue_type: :physical).order(:series_id)

    # Placeholder for PDF generation logic
    # respond_to do |format|
    #   format.html # A page showing what will be printed, or an error
    #   format.pdf do
    #     pdf = Prawn::Document.new
    #     pdf.text "Treasure Hunt: #{@game.name}", size: 20, style: :bold
    #     @physical_clues.each_slice(4) do |clue_batch| # 4 clues per page
    #       clue_batch.each_with_index do |clue, index|
    #         pdf.move_down 20
    #         pdf.text "Clue ##{clue.series_id} (Code: #{clue.unique_code})", style: :bold
    #         pdf.text "Riddle for next clue: #{clue.next_clue_riddle}"
    #         pdf.text "Location Add-on: #{clue.location_addon}" if clue.location_addon.present?
    #         pdf.stroke_horizontal_rule if index < clue_batch.size - 1 && index < 3 # Don't draw after last on page
    #       end
    #       pdf.start_new_page unless clue_batch == @physical_clues.each_slice(4).to_a.last
    #     end
    #     send_data pdf.render, filename: "#{@game.public_code}_clues.pdf",
    #                           type: "application/pdf",
    #                           disposition: "inline" # or "attachment"
    #   end
    # end
    render plain: "PDF printing for physical clues of game #{@game.name} - Implement with Prawn."
  end


  private

  def set_game_and_progress
    @game = current_game_for_player # From ApplicationController
    return unless @game # current_game_for_player handles redirect if not found/active

    # This is a simplified way to get/create player progress.
    # A more robust solution would be in a dedicated controller or service
    # when the player first "joins" the game by providing a nickname and language.
    # For now, we assume session[:player_token_for_game_GAMEID] is set.

    @player_progress = current_player_progress(@game)

    unless @player_progress
      # If no progress, maybe redirect to a "join game" screen
      # For this example, if a player tries to access a game URL directly without "joining"
      # (i.e., providing nickname/language which would create PlayerProgress and set session token)
      # they are redirected.
      session[:joining_game_public_code] = @game.public_code # Store for redirect after join
      redirect_to root_path, alert: "Please join the game with a nickname and language first!"
      return
    end

    # Set locale based on player's preference stored in their progress
    if @player_progress.language.present? && User::VALID_LANGUAGES.include?(@player_progress.language)
      I18n.locale = @player_progress.language
    end
  end

  def ensure_player_can_access_current_clue
    # This is implicitly handled by current_clue_series_id in player_progress.
    # For direct navigation to /clue/:series_id, we use can_access_clue?
    return if params[:action] != "show_clue" # Only for direct clue access by series_id in URL

    requested_series_id = params[:series_id].to_i
    unless @player_progress.can_access_clue?(requested_series_id)
      redirect_to play_game_start_path(@game.public_code), alert: "You haven't reached that clue yet!"
    end
  end

  def proceed_to_next_clue(solved_clue)
    next_series_id = solved_clue.series_id + 1
    next_clue = @game.clues.find_by(series_id: next_series_id)

    @player_progress.unlock_clue!(solved_clue.series_id) # Mark current as solved/unlocked

    if next_clue
      @player_progress.update(current_clue_series_id: next_clue.series_id)
      @player_progress.unlock_clue!(next_clue.series_id) # Also unlock the next one immediately for Q&A

      flash[:notice] = "Correct! 🎉 Here's the next clue."
      # If Q&A, we show the next clue directly.
      # If it were physical, we'd show the riddle for the next clue (which is part of current_clue's data).
      # But since Q&A just reveals the next Q, we go to it.
      redirect_to play_game_clue_path(@game.public_code, series_id: next_clue.series_id)
    else
      # All clues solved!
      @player_progress.update(current_clue_series_id: next_series_id) # Mark as beyond last clue
      redirect_to play_game_start_path(@game.public_code), notice: "Woohoo! You've solved all the clues! TREASURE HUNT COMPLETE! 🏆"
    end
  end
end
EOF

# --- Create HomeController ---
log "Creating basic HomeController..."
cat << EOF > app/controllers/home_controller.rb
class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index, :find_game] # Allow unauth access to homepage

  # GET /
  def index
    # Homepage: Input for game public_code, language selection, nickname
    @game_code = session.delete(:joining_game_public_code) || params[:game_code]
    @available_languages = User::VALID_LANGUAGES.map { |lang| [t("languages.\#{lang}", default: lang.upcase), lang] }
  end

  # POST /find_game
  def find_game
    public_code = params[:public_code]&.strip&.upcase
    nickname = params[:nickname]&.strip
    language = params[:language]

    game = Game.active.find_by(public_code: public_code)

    if game.nil?
      redirect_to root_path, alert: "Oops! Game not found or not currently active. Check the code and try again! 🧐"
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

    # Create or find PlayerProgress
    # For simplicity, let's always create a new one for now.
    # A more robust system might try to resume if a token exists.
    player_progress = game.player_progresses.create(
      nickname: nickname,
      language: language,
      # player_token will be auto-generated by model callback
      # current_clue_series_id defaults to 1
      # unlocked_clue_series_ids defaults to [1]
    )

    if player_progress.persisted?
      session["player_token_for_game_\#{game.id}"] = player_progress.player_token
      session[:player_language] = player_progress.language # For I18n in ApplicationController
      redirect_to play_game_start_path(game_public_code: game.public_code), notice: "Welcome, \#{nickname}! Let the treasure hunt begin! 🚀"
    else
      redirect_to root_path(game_code: public_code), alert: "Could not start the game. Errors: \#{player_progress.errors.full_messages.join(', ')}"
    end
  end
end
EOF

# --- Create GamesController ---
log "Creating basic GamesController..."
cat << EOF > app/controllers/games_controller.rb
class GamesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game, only: %i[show edit update destroy map_view player_status]
  before_action :authorize_owner_or_admin, only: %i[show edit update destroy map_view player_status]

  # GET /games or /dashboard
  def index
    @games = current_user.admin? ? Game.all.order(created_at: :desc) : current_user.games.order(created_at: :desc)
  end

  # GET /games/1
  def show
    # @game is set by set_game
    # Eager load clues for display
    @clues = @game.clues.order(:series_id)
  end

  # GET /games/new
  def new
    @game = current_user.games.build
    # Set default clue type from user preference or a general default if desired
    @game.default_clue_type ||= :Youtube
  end

  # POST /games
  def create
    @game = current_user.games.build(game_params)
    if @game.save
      redirect_to @game, notice: 'Game was successfully created. Time to add some clues! 🕵️'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /games/1/edit
  def edit
    # @game is set by set_game
  end

  # PATCH/PUT /games/1
  def update
    if @game.update(game_params)
      redirect_to @game, notice: 'Game was successfully updated. ✨'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /games/1
  def destroy
    @game.destroy
    redirect_to games_url, notice: 'Game was successfully obliterated. 💣', status: :see_other
  end

  # GET /games/1/map_view
  def map_view
    # @physical_clues = @game.clues.where(clue_type: :physical).where.not(geo_x: nil, geo_y: nil)
    # Render a view with JS to display these on a map.
    # This will require Google Maps API key and JS.
    render plain: "Map view for game '#{@game.name}'. Implement with Google Maps JS API. #{@game.clues.where(clue_type: :physical).count} physical clues."
  end

  # GET /games/1/player_status
  def player_status
    # @player_progresses = @game.player_progresses.order(updated_at: :desc)
    # This page would ideally use Turbo Streams for real-time updates.
    render plain: "Player status for game '#{@game.name}'. #{@game.player_progresses.count} players. Implement with Turbo Streams."
  end


  private

  def set_game
    @game = Game.find(params[:id])
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
log "Creating basic CluesController..."
cat << EOF > app/controllers/clues_controller.rb
class CluesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :set_clue, only: %i[edit update destroy]
  before_action :authorize_owner_or_admin_for_game

  # No index or show for clues directly, managed under game.

  # GET /games/:game_id/clues/new
  def new
    @clue = @game.clues.build
    @clue.clue_type = @game.default_clue_type # Pre-fill from game's default
    # Pre-fill next series_id
    max_series_id = @game.clues.maximum(:series_id) || 0
    @clue.series_id = max_series_id + 1
  end

  # POST /games/:game_id/clues
  def create
    @clue = @game.clues.build(clue_params)
    # unique_code is generated by model if not provided

    if @clue.save
      # Trigger game validation after adding a clue - this might be complex
      # or rely on game's own validation on its next save.
      # For now, assume clue saves independently.
      # @game.validate # to check clue sequence, but this doesn't save the game
      redirect_to game_path(@game, anchor: "clue-#{@clue.id}"), notice: 'Clue was successfully added! 💡'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /games/:game_id/clues/:id/edit
  def edit
    # @clue is set
  end

  # PATCH/PUT /games/:game_id/clues/:id
  def update
    if @clue.update(clue_params)
      redirect_to game_path(@game, anchor: "clue-#{@clue.id}"), notice: 'Clue was successfully updated. 👍'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /games/:game_id/clues/:id
  def destroy
    @clue.destroy
    # Consider game validation implications here too.
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
      :question, :answer, :visual_description, # For QuestionAnswer
      :next_clue_riddle, :location, :geo_x, :geo_y, :location_addon # For Physical
    )
  end
end
EOF

# --- Devise Views (optional, but good for customization) ---
# log "Generating Devise views..."
# bundle exec rails g devise:views

# --- Locales for languages ---
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
# Add other language files similarly (it.yml, fr.yml, etc.)

# --- Database Seeds ---
log "Populating db/seeds.rb..."
cat << EOF > db/seeds.rb
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
require 'ricclib/color' # For colorful seed output

puts Ricclib::Color.yellow("Seeding database for TrHuGa... 🌱")

# === Admin User ===
admin_email = ENV.fetch('ADMIN_EMAIL', 'palladiusbonton@gmail.com')
admin_password = ENV.fetch('ADMIN_PASSWORD', 'aVerySecurePassword123!') # Ensure this is strong for real use

puts Ricclib::Color.blue("Creating admin user...")
admin_user = User.find_or_create_by!(email: admin_email) do |user|
  user.password = admin_password
  user.password_confirmation = admin_password
  user.is_admin = true
  user.language = 'en' # Default language for admin
end
if admin_user.persisted?
  puts Ricclib::Color.green("Admin user '#{admin_user.email}' #{admin_user.newly_created? ? 'created' : 'found'}.")
else
  puts Ricclib::Color.red("Failed to create admin user: #{admin_user.errors.full_messages.join(', ')}")
end

# === Sample Game 1: Q&A - "Riddles in the Digital Park" ===
puts Ricclib::Color.blue("Creating Sample Q&A Game...")
game1 = Game.find_or_create_by!(public_code: "RIDL01") do |g|
  g.user = admin_user
  g.name = "Riddles in the Digital Park"
  g.start_date = Time.current - 1.day
  g.end_date = Time.current + 30.days
  g.published = true
  g.default_clue_type = :Youtube
  g.context = "A fun riddle game for kids aged 6-10. Focus on animals and nature."
end

if game1.persisted?
  puts Ricclib::Color.green("Game '#{game1.name}' #{game1.newly_created? ? 'created' : 'found'}.")

  Clue.find_or_create_by!(game: game1, series_id: 1) do |c|
    c.clue_type = :Youtube
    c.question = "I have a trunk, but I'm not a car. I have big ears, but can't hear you from far. What am I?"
    c.answer = "Elephant"
    c.parent_advisory = "First clue, displayed automatically."
    c.visual_description = "A friendly cartoon elephant waving its trunk."
    # unique_code will be auto-generated
  end

  Clue.find_or_create_by!(game: game1, series_id: 2) do |c|
    c.clue_type = :Youtube
    c.question = "I have stripes, but I'm not a zebra. I live in the jungle and say 'Roar!'. What am I?"
    c.answer = "Tiger"
    c.parent_advisory = "Revealed after answering Clue 1 correctly."
    c.visual_description = "A majestic tiger with orange and black stripes."
  end

  Clue.find_or_create_by!(game: game1, series_id: 3) do |c|
    c.clue_type = :Youtube
    c.question = "I can fly, but I have no wings. I cry, but I have no eyes. What am I?"
    c.answer = "Cloud"
    c.parent_advisory = "Revealed after answering Clue 2 correctly."
    c.visual_description = "A fluffy white cloud in a blue sky."
  end
  # Validate the game to ensure clue sequence is okay after creation
  game1.save # This will trigger validations including clue sequence.
  if game1.errors.any?
    puts Ricclib::Color.red("Warning: Game '#{game1.name}' has validation errors after adding clues: #{game1.errors.full_messages.join(', ')}")
  end

else
  puts Ricclib::Color.red("Failed to create Game 1: #{game1.errors.full_messages.join(', ')}")
end


# === Sample Game 2: Physical - "Zürich Lakeside Adventure" ===
puts Ricclib::Color.blue("Creating Sample Physical Game in Zürich...")
game2 = Game.find_or_create_by!(public_code: "ZURI01") do |g|
  g.user = admin_user
  g.name = "Zürich Lakeside Adventure"
  g.start_date = Time.current - 1.day
  g.end_date = Time.current + 30.days
  g.published = true
  g.default_clue_type = :physical
  g.context = "A physical treasure hunt around Lake Zürich for kids aged 8-12. Encourages observation and light walking."
end

if game2.persisted?
  puts Ricclib::Color.green("Game '#{game2.name}' #{game2.newly_created? ? 'created' : 'found'}.")

  Clue.find_or_create_by!(game: game2, series_id: 1) do |c|
    c.clue_type = :physical
    c.parent_advisory = "Start at Bürkliplatz. Give this first clue to the kids directly."
    c.next_clue_riddle = "Where flowers bloom and boats set sail, find the big clock that tells a tale. (Hint: Near the lake ferry terminal)"
    c.location = "Bürkliplatz, Zürich, Switzerland"
    c.geo_x = 8.5409 # Longitude
    c.geo_y = 47.3653 # Latitude
    c.location_addon = "Near the main flowerbed facing the lake."
  end

  Clue.find_or_create_by!(game: game2, series_id: 2) do |c|
    c.clue_type = :physical
    c.parent_advisory = "Hide this clue near the ZSG Ferry Terminal clock at Bürkliplatz."
    c.next_clue_riddle = "I guard the entrance to an old church, with two tall towers. Lions watch nearby. What am I? (Hint: A famous Münster)"
    c.location = "ZSG Bürkliplatz (See), Zürich, Switzerland"
    c.geo_x = 8.5415
    c.geo_y = 47.3660
    c.location_addon = "Tucked under the information board by the large clock."
  end

  Clue.find_or_create_by!(game: game2, series_id: 3) do |c|
    c.clue_type = :physical
    c.parent_advisory = "Hide this clue at the main entrance of Grossmünster, perhaps near one of the lion statues if safe and permitted."
    c.next_clue_riddle = "Cross the river on a bridge named after a vegetable, and find a toy store with a giant bear! The final treasure is there!"
    c.location = "Grossmünster, Zwinglipl. 7, 8001 Zürich, Switzerland"
    c.geo_x = 8.543 Grossmünster
    c.geo_y = 47.369 Grossmünster
    c.location_addon = "At the base of the northernmost lion statue (if applicable and safe) or a nearby bench."
  end

  Clue.find_or_create_by!(game: game2, series_id: 4) do |c| # The "Treasure" clue
    c.clue_type = :physical
    c.parent_advisory = "This is the final treasure location. Place the 'treasure' (e.g. small gifts, cake) at Franz Carl Weber toy store on Bahnhofstrasse after crossing Gemüsebrücke (Rathausbrücke)."
    c.next_clue_riddle = "Congratulations! You found the final spot! Look for your 'TREASURE' nearby, perhaps guarded by a friendly store employee or hidden by your game master!"
    c.location = "Franz Carl Weber, Bahnhofstrasse 62, 8001 Zürich, Switzerland"
    c.geo_x = 8.5390 # Bahnhofstrasse
    c.geo_y = 47.3721 # Bahnhofstrasse
    c.location_addon = "Inside or just outside Franz Carl Weber. The 'treasure' should be waiting!"
  end

  game2.save # Trigger validations
  if game2.errors.any?
    puts Ricclib::Color.red("Warning: Game '#{game2.name}' has validation errors after adding clues: #{game2.errors.full_messages.join(', ')}")
  end

else
  puts Ricclib::Color.red("Failed to create Game 2: #{game2.errors.full_messages.join(', ')}")
end


# Ensure all clues get unique codes if they were just created
[game1, game2].each do |game|
  next unless game.persisted?
  game.clues.where(unique_code: nil).find_each do |clue|
    clue.send(:generate_unique_code) # Call private method for seeding
    unless clue.save
        puts Ricclib::Color.red("Failed to save clue #{clue.id} for game #{game.name} after generating unique code: #{clue.errors.full_messages.join(', ')}")
    end
  end
  # Re-validate and save the game to check clue sequence integrity.
  unless game.valid?
    puts Ricclib::Color.red("Game '#{game.name}' is invalid after seeding clues: #{game.errors.full_messages.join(', ')}")
  else
    puts Ricclib::Color.green("Game '#{game.name}' and its clues seeded successfully.")
  end
end

puts Ricclib::Color.yellow("Seeding finished! 🎉")

# How to check if User.newly_created? (not a method)
# Check if admin_user.id_previously_changed? or compare created_at with Time.current
# For simplicity, the find_or_create_by! block only runs on creation.
# The boolean result of find_or_create_by! itself isn't directly "newly_created"
# but we can infer based on whether the block was executed.
# A simple way: check if it was persisted before the block. For this script, it's fine.

module ActiveRecord
  class Base
    def newly_created?
      @newly_created == true
    end

    def self.find_or_create_by!(*args, &block)
      record = find_by(*args)
      if record
        record.instance_variable_set(:@newly_created, false)
        return record
      else
        record = new(*args)
        record.instance_variable_set(:@newly_created, true)
        block.call(record) if block
        record.save!
        return record
      end
    end
  end
end

EOF


# --- Final Steps ---
log "Running bundle exec rails db:prepare to create DB and load schema (if not exists)..."
bundle exec rails db:prepare # Creates DB if not exists, loads schema, does not run migrations if DB exists and schema is current.
# Use db:migrate if you prefer running migrations explicitly right after generation
# bundle exec rails db:migrate

log "Running bundle exec rails db:seed..."
bundle exec rails db:seed

# --- Git Init ---
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  log "Initializing Git repository..."
  git init -b main
  git add .
  git commit -m "🎉 Initial project structure for TrHuGa by sbrodola.sh"
  log "Git repository initialized and initial commit made."
else
  warn "Git repository already initialized. Skipping git init."
fi


log "TrHuGa Rails App Generation Complete! 🥳"
info "Next steps:"
info "1. cd ${APP_NAME}"
info "2. Review all generated files, especially models, controllers, and routes."
info "3. Update '.env.dist' to '.env' and fill in your actual API keys and secrets."
info "4. Customize Devise views if needed: rails g devise:views"
info "5. Start developing your views and implementing the LLM logic, Maps API, etc."
info "6. Run 'just dev' or './bin/dev' to start the development server."
echo ""
echo "${bold}${blue}May your code be bug-free and your treasures plentiful! 🗺️💎${normal}"
