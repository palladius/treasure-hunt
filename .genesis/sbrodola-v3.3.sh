#!/bin/bash
# sbrodola.sh - Generates the Treasure Hunt Game Rails application (v3.3 - sed fix + FAST_SKIP_STUFF)

# --- CONFIGURATION TOGGLE ---
# Set to true for faster initial runs: uses SQLite, skips test gems & docs.
# Set to false for the full PostgreSQL setup with all gems.
FAST_SKIP_STUFF=true
# --- END CONFIGURATION TOGGLE ---

# Stop at the first big error - a treasure hunter's motto!
set -euo pipefail

APP_NAME="treasure-hunt-game"
RUBY_VERSION="3.4.4"
RAILS_VERSION_CONSTRAINT="~> 8.0.2"

# --- Helper Functions ---
bold=$(tput bold); normal=$(tput sgr0); green=$(tput setaf 2); yellow=$(tput setaf 3); blue=$(tput setaf 4)
log() { echo "${bold}${green}>>> ${1}${normal}"; }
warn() { echo "${bold}${yellow}!!! ${1}${normal}"; }
info() { echo "${bold}${blue}--- ${1}${normal}"; }

# --- Check for Rails & Bundler ---
if ! command -v rails &> /dev/null; then warn "Rails not found. Install Rails (${RAILS_VERSION_CONSTRAINT}) and Ruby ${RUBY_VERSION}."; exit 1; fi
if ! command -v bundle &> /dev/null; then warn "Bundler not found. Install Bundler (gem install bundler)."; exit 1; fi

log "Starting ${APP_NAME} Rails App Generation (v3.3 - FAST_SKIP_STUFF=${FAST_SKIP_STUFF})..."

# --- Determine Database Option ---
DB_OPT="--database=postgresql"
if [ "$FAST_SKIP_STUFF" = "true" ]; then
  DB_OPT="--database=sqlite3"
  info "FAST_SKIP_STUFF is true. Using SQLite for faster setup."
fi

# --- Create Rails App ---
info "Generating new Rails app: ${APP_NAME} with ${DB_OPT}"
rails new "${APP_NAME}" ${DB_OPT} --css=tailwind --javascript=importmap -T

cd "${APP_NAME}"
log "Changed directory to $(pwd)"

# --- Set Ruby Version ---
info "Setting Ruby version to ${RUBY_VERSION} in .ruby-version"
echo "${RUBY_VERSION}" > .ruby-version

# --- Ensure Rails and Ruby versions in Gemfile ---
info "Ensuring correct Ruby and Rails versions in Gemfile..."
if grep -q "gem \"rails\"" Gemfile; then sed -i.bak "s|^gem \"rails\",.*|gem \"rails\", \"${RAILS_VERSION_CONSTRAINT}\"|g" Gemfile && rm -f Gemfile.bak; else echo "gem \"rails\", \"${RAILS_VERSION_CONSTRAINT}\"" >> Gemfile; fi
if grep -q "^ruby \".*\"" Gemfile; then sed -i.bak "s|^ruby \".*\"|ruby \"${RUBY_VERSION}\"|g" Gemfile && rm -f Gemfile.bak; else echo "ruby \"${RUBY_VERSION}\"" | cat - Gemfile > temp_gemfile && mv temp_gemfile Gemfile; fi

# --- Configure Bundler for Speed (if FAST_SKIP_STUFF is true) ---
if [ "$FAST_SKIP_STUFF" = "true" ]; then
  info "Configuring Bundler to skip gem documentation for faster installs."
  bundle config set --local gem.no-document true
fi

# --- Add Gems Surgically using bundle add ---
log "Adding necessary gems using 'bundle add'..."
bundle add devise --version "~> 4.9.3"
bundle add gemini-ai --version "~> 4.2.0"
bundle add http --version "~> 5.2.0"
bundle add prawn --version "~> 2.4.0"
bundle add prawn-table --version "~> 0.2.2"
bundle add matrix # For Prawn dependency on Ruby 3.1+

if [ "$FAST_SKIP_STUFF" = "true" ]; then
  info "FAST_SKIP_STUFF: Skipping dotenv-rails and test gems (rspec, factory_bot, faker)."
  if ! grep -q "gem 'sqlite3'" Gemfile && ! grep -q 'gem "sqlite3"' Gemfile; then
    bundle add sqlite3 --version "~> 1.7"
  fi
else
  bundle add dotenv-rails --group "development, test" --version "~> 2.8.1"
  bundle add rspec-rails --group "development, test" --version "~> 6.1.2"
  bundle add factory_bot_rails --group "development, test" --version "~> 6.4.0"
  bundle add faker --group "development, test" --version "~> 3.3.0"
fi

log "Running bundle install..."
bundle install

# --- Devise Setup ---
log "Setting up Devise..."
bundle exec rails g devise:install
info "Creating User model with Devise (is_admin:boolean, language:string)..."
bundle exec rails g devise User is_admin:boolean language:string

# --- Generate Models ---
log "Generating models..."
bundle exec rails g model Game name:string public_code:string:uniq start_date:datetime end_date:datetime published:boolean default_clue_type:integer context:text user:references
bundle exec rails g model Clue series_id:integer unique_code:string parent_advisory:text published:boolean clue_type:integer question:string answer:string visual_description:string next_clue_riddle:text location:string geo_x:float geo_y:float location_addon:string game:references
bundle exec rails g model PlayerProgress game:references nickname:string language:string current_clue_series_id:integer unlocked_clue_series_ids:text player_token:string:uniq

# --- Update Migrations for Indexes and Defaults (Robust sed) ---
log "Updating migrations for indexes and default values..."

get_latest_migration_file() {
  # Helper to get the full path of the latest migration matching a pattern
  ls db/migrate/*_$1.rb | sort | tail -n 1
}

# Modify CreateGames migration
GAME_MIGRATION_FILE=$(get_latest_migration_file "create_games")
info "Updating migration: ${GAME_MIGRATION_FILE}"
GAME_PUBLIC_CODE_INDEX_TEXT="    add_index :games, :public_code, unique: true"
sed -i.bak "/t.string :public_code/a\\
${GAME_PUBLIC_CODE_INDEX_TEXT}
" "$GAME_MIGRATION_FILE"
sed -i.bak 's/\(t.boolean :published\)/\1, default: true/' "$GAME_MIGRATION_FILE"
rm -f "${GAME_MIGRATION_FILE}.bak"


# Modify CreateClues migration
CLUE_MIGRATION_FILE=$(get_latest_migration_file "create_clues")
info "Updating migration: ${CLUE_MIGRATION_FILE}"
CLUE_INDEX_TEXT_1="    add_index :clues, [:game_id, :unique_code], unique: true"
CLUE_INDEX_TEXT_2="    add_index :clues, [:game_id, :series_id], unique: true"
sed -i.bak "/t.references :game, null: false, foreign_key: true/a\\
${CLUE_INDEX_TEXT_1}\\
${CLUE_INDEX_TEXT_2}
" "$CLUE_MIGRATION_FILE"
sed -i.bak 's/\(t.boolean :published\)/\1, default: true/' "$CLUE_MIGRATION_FILE"
rm -f "${CLUE_MIGRATION_FILE}.bak"


# Modify CreatePlayerProgresses migration
PLAYER_PROGRESS_MIGRATION_FILE=$(get_latest_migration_file "create_player_progresses")
info "Updating migration: ${PLAYER_PROGRESS_MIGRATION_FILE}"
PLAYER_TOKEN_INDEX_TEXT="    add_index :player_progresses, :player_token, unique: true"
sed -i.bak "/t.string :player_token/a\\
${PLAYER_TOKEN_INDEX_TEXT}
" "$PLAYER_PROGRESS_MIGRATION_FILE"
sed -i.bak 's/\(t.integer :current_clue_series_id\)/\1, default: 1/' "$PLAYER_PROGRESS_MIGRATION_FILE"
rm -f "${PLAYER_PROGRESS_MIGRATION_FILE}.bak"


# Modify DeviseCreateUsers migration
DEVISE_USERS_MIGRATION_FILE=$(get_latest_migration_file "devise_create_users")
info "Updating migration: ${DEVISE_USERS_MIGRATION_FILE} for User defaults"
if grep -q "t.boolean :is_admin" "$DEVISE_USERS_MIGRATION_FILE"; then
    if ! grep -q "t.boolean :is_admin, default: false" "$DEVISE_USERS_MIGRATION_FILE"; then
        sed -i.bak 's/\(t.boolean :is_admin\)/\1, default: false, null: false/' "$DEVISE_USERS_MIGRATION_FILE"
    else
        info "'is_admin' column in Devise migration already has default. Skipping modification."
    fi
else
    warn "Could not find 't.boolean :is_admin' in Devise migration to set default. Please check: ${DEVISE_USERS_MIGRATION_FILE}"
fi
rm -f "${DEVISE_USERS_MIGRATION_FILE}.bak"

# --- Generate Controllers ---
log "Generating controllers..."
bundle exec rails g controller HomeController index find_game
bundle exec rails g controller PlayerInterfaceController show submit_answer
bundle exec rails g controller Games --skip-routes
bundle exec rails g controller Clues --parent=Game --skip-routes

# --- Configure Routes ---
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
    member { get :map_view; get :player_status }
    resources :clues, except: [:index, :show]
  end
  get "dashboard" => "games#index", as: :user_dashboard
end
EOF

# --- Create ricclib/color.rb ---
log "Creating ricclib/color.rb..."
mkdir -p lib/ricclib
cat << EOF > lib/ricclib/color.rb
module Ricclib; module Color
COLORS={black:30,red:31,green:32,yellow:33,blue:34,magenta:35,cyan:36,white:37,default:39}.freeze
STYLES={bold:1,underline:4,normal:0}.freeze
def self.colorize(t,c,s=nil);cc=COLORS[c.to_sym]||COLORS[:default];sc=s ?"#{STYLES[s.to_sym]};":"";"\e[#{sc}#{cc}m#{t}\e[#{STYLES[:normal]}m";end
COLORS.each_key{|k|define_singleton_method(k){|t|colorize(t,k)}}
STYLES.each_key{|k|next if k==:normal;define_singleton_method(k){|t,c=:default|colorize(t,c,k)}}
end;end
EOF
if ! grep -q "config.autoload_paths << Rails.root.join('lib')" config/application.rb; then
  sed -i.bak '/class Application < Rails::Application/a\    config.autoload_paths << Rails.root.join("lib")' config/application.rb && rm -f config/application.rb.bak
fi

# --- Create justfile ---
log "Creating justfile..."
cat << EOF > justfile
# justfile for ${APP_NAME} (FAST_SKIP_STUFF aware)
APP_NAME := ${APP_NAME}
DOCKER_IMAGE_NAME := \$(APP_NAME)-app
DOCKER_TAG := latest
# Determine if FAST_SKIP_STUFF was effectively true during script generation for conditional commands
# This is a proxy, actual value was in shell script. User should know.
# For simplicity, justfile commands might note differences.
FAST_MODE_COMMENT := "# Test/Lint may behave differently if generated in FAST_SKIP_STUFF=true mode"

default: list; list:; @just --list

setup: ; @echo "📦 Deps..."; bundle install; @echo "⚙️ DB prep..."; rails db:prepare; @echo "🌱 Seed..."; rails db:seed; @echo "✅ Done!" \$(FAST_MODE_COMMENT)
dev: ; @echo "🚀 Dev server..."; ./bin/dev
db-migrate: ; rails db:migrate; db-seed: ; rails db:seed; db-reset: ; rails db:reset
console: ; rails c

test: ; \
  if [ -d "spec" ] && bundle show rspec-rails > /dev/null 2>&1; then \
    echo "🧪 RSpec..."; bundle exec rspec; \
  else \
    echo "🧪 Tests skipped (RSpec not setup or FAST_SKIP_STUFF mode was active)."; \
  fi

build-docker:
    @echo "Building Docker image \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}..." \$(FAST_MODE_COMMENT)
    @echo "Note: For full PostgreSQL setup, ensure FAST_SKIP_STUFF=false when generating project."
    if [ -f Dockerfile ]; then docker build . -t \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}; else echo "Dockerfile missing."; fi
run-docker:
    @echo "Run Docker (expects PostgreSQL setup from FAST_SKIP_STUFF=false)..." \$(FAST_MODE_COMMENT)
    if [ -f Dockerfile ]; then docker run -p 3000:3000 -e RAILS_MASTER_KEY=\$(cat config/master.key) -e DATABASE_URL="postgresql://postgres:password@host.docker.internal:5432/\${APP_NAME}_development" \${DOCKER_IMAGE_NAME}:\${DOCKER_TAG}; else echo "Dockerfile/image missing."; fi

lint: ; \
  if bundle show rubocop > /dev/null 2>&1; then \
    bundle exec rubocop || echo "RuboCop issues."; \
  else \
    echo "RuboCop missing (likely not added if in FAST_SKIP_STUFF mode or not in Gemfile)."; \
  fi
lint-fix: ; \
  if bundle show rubocop > /dev/null 2>&1; then \
    bundle exec rubocop -A || echo "RuboCop fix."; \
  else \
    echo "RuboCop missing."; \
  fi
EOF

# --- Create .env.dist ---
log "Creating .env.dist..."
cat << EOF > .env.dist
# .env.dist for ${APP_NAME}
# For PostgreSQL (when FAST_SKIP_STUFF=false):
# DATABASE_URL="postgresql://USER:PASS@localhost:5432/${APP_NAME}_development"
# For SQLite (when FAST_SKIP_STUFF=true), DATABASE_URL is usually not needed here.
GEMINI_API_KEY="YOUR_GEMINI_API_KEY"
ADMIN_EMAIL="palladiusbonton@gmail.com"
ADMIN_PASSWORD="aVerySecurePassword123!"
EOF
if ! grep -q "^\.env$" .gitignore; then echo ".env" >> .gitignore; fi

# --- Populate Model Files ---
log "Populating model files (app/models/)..."
cat << EOF > app/models/user.rb
class User<ApplicationRecord;devise :database_authenticatable,:registerable,:recoverable,:rememberable,:validatable;has_many :games,dependent: :destroy;VALID_LANGUAGES=%w[en it fr pt de pl ja].freeze;validates :language,inclusion:{in:VALID_LANGUAGES,message:"%{value} not valid"},allow_nil:true;def admin?;is_admin;end;end
EOF
cat << EOF > app/models/game.rb
class Game<ApplicationRecord;belongs_to :user;has_many :clues,->{order(series_id: :asc)},dependent: :destroy,inverse_of: :game;enum default_clue_type:{Youtube:0,physical:1};validates :name,presence:true;validates :public_code,presence:true,uniqueness:{case_sensitive:false},length:{is:6};validates :start_date,:end_date,presence:true;validate :end_date_after_start_date;validate :clues_series_ids_are_consecutive,if: :should_validate_clues?;before_validation :generate_public_code,on: :create;before_save ->{public_code.upcase! if public_code.present?};scope :published,->{where(published:true)};scope :active,->{published.where("start_date <= :today AND end_date >= :today",today:Time.current)};attr_accessor :skip_clue_validation;private;def generate_public_code;loop{self.public_code=SecureRandom.alphanumeric(6).upcase;break unless Game.exists?(public_code:self.public_code)};end;def end_date_after_start_date;errors.add(:end_date,"must be after start")if end_date.present?&&start_date.present?&&end_date<start_date;end;def should_validate_clues?;!@skip_clue_validation && (new_record?||clues.any?(&:changed?)||clues.any?(&:new_record?)||clues.any?(&:marked_for_destruction?));end;def clues_series_ids_are_consecutive;current_clues=clues.reject(&:marked_for_destruction?);return if current_clues.empty?;sorted_ids=current_clues.map(&:series_id).compact.sort;unless sorted_ids.first==1&&sorted_ids.each_with_index.all?{|id,idx|id==idx+1};errors.add(:base,"Clue series_ids must be 1..N. Found: #{sorted_ids.join(', ')}");end;end;end
EOF
cat << EOF > app/models/clue.rb
class Clue<ApplicationRecord;belongs_to :game;enum clue_type:{Youtube:0,physical:1};validates :series_id,presence:true,numericality:{only_integer:true,greater_than:0},uniqueness:{scope: :game_id};validates :unique_code,presence:true,length:{is:4},uniqueness:{scope: :game_id};validates :parent_advisory,:clue_type,presence:true;with_options if::Youtube? do |qa|qa.validates :question,:answer,presence:true;end;with_options if::physical? do |p|p.validates :next_clue_riddle,presence:true;end;before_validation :generate_unique_code,on: :create,if:->{unique_code.blank?};private;def generate_unique_code;loop{self.unique_code=format('%04d',SecureRandom.rand(10000));break unless game&&game.clues.loaded?&&game.clues.target.any?{|c|c!=self&&c.unique_code==self.unique_code};break if game&&!game.clues.where.not(id:self.id).exists?(unique_code:self.unique_code);break if game.nil?};end;end
EOF
cat << EOF > app/models/player_progress.rb
class PlayerProgress<ApplicationRecord;belongs_to :game;serialize :unlocked_clue_series_ids,type:Array,coder:YAML;validates :nickname,:language,:player_token,presence:true;validates :player_token,uniqueness:true;validates :current_clue_series_id,presence:true,numericality:{only_integer:true,geq:1};before_validation :ensure_player_token_and_defaults,on: :create;def ensure_player_token_and_defaults;self.player_token||=SecureRandom.hex(16);self.unlocked_clue_series_ids||=[1];self.current_clue_series_id||=1;end;def unlock_clue!(sid);id=sid.to_i;return false if id<=0;unlocked_clue_series_ids.append(id).sort!.uniq!;self.current_clue_series_id=[current_clue_series_id,id].max;save;end;def can_access_clue?(sid);unlocked_clue_series_ids.include?(sid.to_i);end;end
EOF

# --- Application & Other Controllers ---
log "Configuring controllers..."
cat << EOF > app/controllers/application_controller.rb
class ApplicationController<ActionController::Base;protect_from_forgery with: :exception;before_action :configure_permitted_parameters,if: :devise_controller?;before_action :set_locale;protected;def configure_permitted_parameters;devise_parameter_sanitizer.permit(:sign_up,keys:[:language]);devise_parameter_sanitizer.permit(:account_update,keys:[:language]);end;def set_locale;lang=session[:player_language]||(user_signed_in?&&current_user.language);I18n.locale=User::VALID_LANGUAGES.include?(lang)?lang:I18n.default_locale;end;def current_game_for_player;@current_game_for_player||=Game.active.find_by(public_code:params[:game_public_code]&.upcase);redirect_to(root_path,alert:"Game not found/active.")unless @current_game_for_player;@current_game_for_player;end;def current_player_progress(g);token=session["player_token_for_game_#{g&.id}"];PlayerProgress.find_by(game_id:g&.id,player_token:token)if token&&g;end;end
EOF
cat << EOF > app/controllers/player_interface_controller.rb
class PlayerInterfaceController<ApplicationController;before_action :set_game_and_player_progress;before_action :load_and_authorize_clue,only:[:show_clue];def show;@clue=@game.clues.find_by(series_id:@player_progress.current_clue_series_id);handle_game_completion_or_clue_error;end;def submit_answer;submitted=params[:answer_or_code].to_s.strip;@clue=@game.clues.find_by(series_id:@player_progress.current_clue_series_id);return redirect_to_current_game_start("Current clue missing!")unless @clue;if @clue.Youtube?;correct=submitted.downcase==@clue.answer.downcase;correct ?proceed_to_next_clue(@clue):rerender_clue_with_error("Try again! 🤔");elsif @clue.physical?;handle_physical_clue_submission(submitted,@clue);end;end;def show_clue;render :show;end;def print_clues;game=Game.find_by(public_code:params[:game_public_code]&.upcase);return redirect_to(root_path,alert:"Not auth.")unless game&&current_user&&(game.user==current_user||current_user.admin?);clues=game.clues.where(clue_type: :physical).order(:series_id);render plain:"PDF for '\#{game.name}'. Clues: \#{clues.count}.";end;private;def set_game_and_player_progress;@game=current_game_for_player;return unless @game;@player_progress=current_player_progress(@game);return if @player_progress;session[:joining_game_public_code]=@game.public_code;redirect_to root_path,alert:"Join game first!";end;def load_and_authorize_clue;@clue=@game.clues.find_by(series_id:params[:series_id].to_i);redirect_to_current_game_start("Clue missing.")unless @clue;redirect_to_current_game_start("Not unlocked!")unless @player_progress.can_access_clue?(@clue.series_id);end;def handle_physical_clue_submission(code,riddle_clue);found_clue=@game.clues.find_by(unique_code:code);if found_clue&&found_clue.series_id==riddle_clue.series_id+1;@player_progress.unlock_clue!(found_clue.series_id);flash[:notice]="Correct! 🎉 Next challenge!";redirect_to play_game_clue_path(@game.public_code,series_id:found_clue.series_id);else;msg=found_clue ?"Not next clue. Keep looking! 🧐":"Code wrong. Check it! 🔢";rerender_clue_with_error(msg,riddle_clue);end;end;def proceed_to_next_clue(solved_clue);next_id=solved_clue.series_id+1;@player_progress.unlock_clue!(solved_clue.series_id);if @game.clues.exists?(series_id:next_id);@player_progress.update!(current_clue_series_id:next_id);@player_progress.unlock_clue!(next_id);flash[:notice]="Correct! 🎉 Next clue.";redirect_to play_game_clue_path(@game.public_code,series_id:next_id);else;@player_progress.update!(current_clue_series_id:next_id);redirect_to_current_game_start("Woohoo! TREASURE HUNT COMPLETE! 🏆",:notice);end;end;def handle_game_completion_or_clue_error;if @clue.nil?&&@player_progress.current_clue_series_id > @game.clues.maximum(:series_id).to_i;flash.now[:notice]="Congrats! Hunt complete! 🥳";elsif @clue.nil?;flash.now[:alert]="Error: Clue missing.";end;end;def rerender_clue_with_error(msg,clue=@clue);flash.now[:alert]=msg;@clue=clue;render :show,status: :unprocessable_entity;end;def redirect_to_current_game_start(msg,type=:alert);redirect_to play_game_start_path(@game.public_code),type=>msg;end;end
EOF
cat << EOF > app/controllers/home_controller.rb
class HomeController<ApplicationController;skip_before_action :authenticate_user!,only:[:index,:find_game];def index;@game_code=session.delete(:joining_game_public_code)||params[:game_code];@available_languages=User::VALID_LANGUAGES.map{|c|[t("languages.#{c}",default:c.upcase),c]};end;def find_game;code=params[:public_code]&.strip&.upcase;nick=params[:nickname]&.strip;lang=params[:language];game=Game.active.find_by(public_code:code);return redirect_to_root_alert(code,"Game not found/active. Check code!🧐")unless game;return redirect_to_root_alert(code,"Need a nickname!😎")if nick.blank?;return redirect_to_root_alert(code,"Select language!🗣️")unless User::VALID_LANGUAGES.include?(lang);progress=game.player_progresses.create(nickname:nick,language:lang);if progress.persisted?;session["player_token_for_game_#{game.id}"]=progress.player_token;session[:player_language]=progress.language;redirect_to play_game_start_path(game_public_code:game.public_code),notice:"Welcome, #{nick}! Hunt begins!🚀";else;redirect_to_root_alert(code,"Could not start: #{progress.errors.full_messages.join(', ')}");end;end;private;def redirect_to_root_alert(c,m)redirect_to root_path(game_code:c),alert:m;end;end
EOF
cat << EOF > app/controllers/games_controller.rb
class GamesController<ApplicationController;before_action :authenticate_user!;before_action :set_game_with_clues,only:%i[show edit update destroy map_view player_status];before_action :authorize_owner_or_admin,only:%i[show edit update destroy map_view player_status];def index;@games=current_user.admin? ?Game.all.order(created_at: :desc):current_user.games.order(created_at: :desc);end;def show;end;def new;@game=current_user.games.build(default_clue_type: :Youtube);end;def edit;end;def create;@game=current_user.games.build(game_params);if @game.save;redirect_to @game,notice:'Game created! Add clues!🕵️';else;render :new,status: :unprocessable_entity;end;end;def update;if @game.update(game_params);redirect_to @game,notice:'Game updated.✨';else;render :edit,status: :unprocessable_entity;end;end;def destroy;@game.destroy;redirect_to games_url,notice:'Game obliterated.💣',status: :see_other;end;def map_view;clues=@game.clues.where(clue_type: :physical).where.not(geo_x:nil,geo_y:nil);render plain:"Map for '\#{@game.name}'. \#{clues.count} physical clues.";end;def player_status;progresses=@game.player_progresses.order(updated_at: :desc);render plain:"Status for '\#{@game.name}'. \#{progresses.count} players.";end;private;def set_game_with_clues;@game=Game.includes(:clues).find(params[:id]);end;def authorize_owner_or_admin;redirect_to(games_path,alert:"Not authorized.🛑")unless @game.user==current_user||current_user.admin?;end;def game_params;params.require(:game).permit(:name,:start_date,:end_date,:published,:default_clue_type,:context);end;end
EOF
cat << EOF > app/controllers/clues_controller.rb
class CluesController<ApplicationController;before_action :authenticate_user!;before_action :set_game_and_authorize;before_action :set_clue,only:%i[edit update destroy];def new;@clue=@game.clues.build(clue_type:@game.default_clue_type,series_id:(@game.clues.maximum(:series_id)||0)+1);end;def edit;end;def create;@clue=@game.clues.build(clue_params);if @clue.save;redirect_to game_path(@game,anchor:"clue-#{@clue.id}"),notice:'Clue added!💡';else;render :new,status: :unprocessable_entity;end;end;def update;if @clue.update(clue_params);redirect_to game_path(@game,anchor:"clue-#{@clue.id}"),notice:'Clue updated.👍';else;render :edit,status: :unprocessable_entity;end;end;def destroy;@clue.destroy;redirect_to game_path(@game),notice:'Clue deleted.💨',status: :see_other;end;private;def set_game_and_authorize;@game=Game.find(params[:game_id]);redirect_to(games_path,alert:"Not auth.🚫")unless @game.user==current_user||current_user.admin?;end;def set_clue;@clue=@game.clues.find(params[:id]);end;def clue_params;params.require(:clue).permit(:series_id,:unique_code,:parent_advisory,:published,:clue_type,:question,:answer,:visual_description,:next_clue_riddle,:location,:geo_x,:geo_y,:location_addon);end;end
EOF

# --- Locales for languages ---
log "Adding basic locale structure (config/locales/en.yml)..."
mkdir -p config/locales
cat << EOF > config/locales/en.yml
en:
  hello: "Hello world"
  languages: { en: "English", it: "Italian", fr: "French", pt: "Portuguese", de: "German", pl: "Polish", ja: "Japanese" }
  game: { find_game: "Find Game", enter_code: "Enter Game Code (e.g., R7M5CH)", nickname: "Your Nickname", select_language: "Select Language", start_hunt: "Start Hunt!" }
  clue: { submit_answer: "Submit Answer", submit_code: "Enter Code Found", your_answer_or_code: "Your Answer or Code" }
EOF

# --- Database Seeds ---
log "Populating db/seeds.rb..."
cat << EOF > db/seeds.rb
require 'ricclib/color'
puts Ricclib::Color.yellow("Seeding DB for \#{Rails.application.class.module_parent_name}... 🌱")
def find_or_create_resource!(model,find_attrs,create_attrs={},&block)
r=model.find_by(find_attrs);c=false;unless r;r=model.new(find_attrs.merge(create_attrs));block.call(r)if block_given?;r.save!;c=true;end;[r,c];end
admin_email=ENV.fetch('ADMIN_EMAIL','palladiusbonton@gmail.com');admin_pass=ENV.fetch('ADMIN_PASSWORD','aVerySecurePassword123!')
admin,new_admin=find_or_create_resource!(User,{email:admin_email}){|u|u.password=admin_pass;u.password_confirmation=admin_pass;u.is_admin=true;u.language='en'}
puts Ricclib::Color.green("Admin '\#{admin.email}' \#{new_admin ?'created':'found'}.")
game1,new_g1=find_or_create_resource!(Game,{public_code:"RIDL01"},{user:admin}){|g|g.name="Riddles Park";g.start_date=Time.current-1.day;g.end_date=Time.current+30.days;g.published=true;g.default_clue_type=:Youtube;g.context="Fun riddles"}
if game1.persisted?;puts Ricclib::Color.green("Game '\#{game1.name}' \#{new_g1 ?'created':'found'}.");[{id:1,q:"Trunk, big ears?",a:"Elephant"},{id:2,q:"Stripes, roars?",a:"Tiger"},{id:3,q:"Flies no wings, cries no eyes?",a:"Cloud"}].each{|d|find_or_create_resource!(Clue,{game:game1,series_id:d[:id]},{clue_type: :Youtube,question:d[:q],answer:d[:a],parent_advisory:"Clue #{d[:id]}"})};game1.save;end
game2,new_g2=find_or_create_resource!(Game,{public_code:"ZURI01"},{user:admin}){|g|g.name="Zürich Hunt";g.start_date=Time.current-1.day;g.end_date=Time.current+30.days;g.published=true;g.default_clue_type=:physical;g.context="Hunt in Zürich"}
if game2.persisted?;puts Ricclib::Color.green("Game '\#{game2.name}' \#{new_g2 ?'created':'found'}.");[{id:1,r:"Flowers, boats, big clock?",l:"Bürkliplatz",x:8.5409,y:47.3653},{id:2,r:"Church, towers, lions?",l:"ZSG Bürkliplatz",x:8.5415,y:47.3660},{id:3,r:"Veg bridge, toy store bear?",l:"Grossmünster",x:8.543,y:47.369},{id:4,r:"Final spot! TREASURE!",l:"Franz Carl Weber",x:8.5390,y:47.3721}].each{|d|find_or_create_resource!(Clue,{game:game2,series_id:d[:id]},{clue_type: :physical,parent_advisory:"Clue #{d[:id]}",next_clue_riddle:d[:r],location:d[:l],geo_x:d[:x],geo_y:d[:y]})};game2.save;end
[game1,game2].compact.each{|g|g.clues.where(unique_code:nil).find_each{|c|c.save(validate:false)};if g.valid?;puts Ricclib::Color.green("Game '\#{g.name}' valid.");else;puts Ricclib::Color.red("Game '\#{g.name}' invalid: \#{g.errors.full_messages.join(', ')}");end}
puts Ricclib::Color.yellow("Seeding done! 🎉")
EOF

# --- Final Steps ---
log "Running bundle exec rails db:prepare (creates DB, loads schema, runs pending migrations)..."
bundle exec rails db:prepare

log "Running bundle exec rails db:seed..."
bundle exec rails db:seed

if [ "$FAST_SKIP_STUFF" != "true" ]; then
  if bundle show rspec-rails > /dev/null 2>&1; then
      log "Setting up RSpec..."
      bundle exec rails generate rspec:install
  fi
fi

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  log "Initializing Git repository..."
  git init -b main && git add . && git commit -m "🎉 Initial project: ${APP_NAME} by sbrodola.sh (v3.3)"
  log "Git repository initialized."
else
  warn "Git repository already exists. You may want to commit changes."
fi

log "${APP_NAME} Rails App Generation Complete! 🥳"
info "FAST_SKIP_STUFF was set to: ${FAST_SKIP_STUFF}"
if [ "$FAST_SKIP_STUFF" = "true" ]; then
  info "This was a FAST run (SQLite, no test gems/docs). For full setup, set FAST_SKIP_STUFF=false and re-run."
fi
info "Next steps: cd ${APP_NAME}, review files, update .env (if needed), and 'just dev' to start!"
echo ""
echo "${bold}${blue}May your code be bug-free and your treasures plentiful! 🗺️💎${normal}"
