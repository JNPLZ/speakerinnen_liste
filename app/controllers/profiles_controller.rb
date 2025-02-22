# frozen_string_literal: true

class ProfilesController < ApplicationController
  include ProfilesHelper
  include CategoriesHelper
  include ActsAsTaggableOn::TagsHelper
  include SearchHelper

  before_action :set_profile, only: %i[show edit update destroy require_permission]

  before_action :require_permission, only: %i[edit destroy update]

  respond_to :json

  def index
    if params[:search]
      @profiles = profiles_for_search
      # sum of search results concerning certain attributes
      @aggs = @profiles.response.aggregations
      @aggs_languages = @aggs[:lang][:buckets]
      @aggs_cities = @aggs[:city][:buckets]
      @aggs_states = @aggs[:state][:buckets]
      @aggs_countries = @aggs[:country][:buckets]
      @three_sample_categories = Category.all.sample(3)
    elsif params[:tag_filter]&.present?
      @tags = params[:tag_filter].split(/\s*,\s*/)
      @profiles = profiles_with_tags
      # redirect_to profiles_path(:anchor => "speakers")
    elsif params[:category_id]
      @profiles = profiles_for_category
    else
      @profiles = profiles_for_index
    end

    @profiles_count = @profiles.total_count

    # for the tags filter module that is available all the time at the profile index view
    # is needed for the colors of the tags
    @category =
      if params[:category_id]
        Category.find(params[:category_id])
      elsif params[:tag_filter]
        if params[:tag_filter].empty?
          redirect_to profiles_url(anchor: "top"), notice: I18n.t('flash.profiles.no_tags_selected')
          return
        end
        last_tag = params[:tag_filter].split(/\s*,\s*/).last
        last_tag_id = ActsAsTaggableOn::Tag.where(name: last_tag).last.id
        Category.select{|cat| cat.tag_ids.include?(last_tag_id)}.last
      else
        Category.first
      end
    @categories = Category.sorted_categories
    Category.all.includes(:translations).each do |category|
      tags = ActsAsTaggableOn::Tag
        .belongs_to_category(category.id)
        .with_published_profile
        .with_regional_profile(current_region)
        .translated_in_current_language_and_not_translated(I18n.locale)
      tags = tags.belongs_to_more_than_one_profile unless current_region
      instance_variable_set("@tags_#{category.short_name}", tags).most_used(100)
    end
  end

  def show
    if @profile.published? || can_edit_profile?(current_profile, @profile)
      @message = Message.new
      @medialinks = @profile.medialinks.order(:position)
    else
      redirect_to profiles_url, notice: I18n.t('flash.profiles.show_no_permission')
    end
  end

  # should reuse the devise view
  def edit
    build_missing_translations(@profile)
  end

  def update
    if @profile.update(profile_params)
      redirect_to @profile, notice: I18n.t('flash.profiles.updated', profile_name: @profile.name_or_email)
    elsif current_profile
      build_missing_translations(@profile)
      render action: 'edit'
    end
  end

  def destroy
    @profile.destroy
    redirect_to profiles_url, notice: I18n.t('flash.profiles.destroyed', profile_name: @profile.name_or_email)
  end

  def require_permission
    return if can_edit_profile?(current_profile, @profile)

    redirect_to profiles_url, notice: I18n.t('flash.profiles.no_permission')
  end

  def render_footer?
    true
  end

  def typeahead
    suggestions = Profile.typeahead(params[:q], region: current_region.to_s)
    suggestions_array = suggestions.map do |suggestion|
      {'text': suggestion.titleize}
    end
    suggestions_array.push('_source': {})
    respond_with(suggestions_array)
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_profile
    @profile = Profile.friendly.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def profile_params
    params.require(:profile).permit(
      :email,
      :password,
      :password_confirmation,
      :remember_me,
      :country,
      :state,
      { iso_languages: [] },
      :firstname,
      :lastname,
      :content,
      :name,
      :topic_list,
      :medialinks,
      :slug,
      :admin_comment,
      :main_topic_en,
      :main_topic_de,
      :bio_en,
      :bio_de,
      :twitter_de,
      :twitter_en,
      :website_de,
      :website_en,
      :website_2_de,
      :website_2_en,
      :website_3_de,
      :website_3_en,
      :profession_en,
      :profession_de,
      :city_de,
      :city_en,
      :image,
      :copyright,
      :personal_note_de,
      :personal_note_en,
      :willing_to_travel,
      :nonprofit,
      :inactive,
      feature_ids: [],
      service_ids: [],
      translations_attributes: %i[id bio main_topic twitter website profession city locale]
    )
  end

  def profiles_for_category
    tag_names =
      ActsAsTaggableOn::Tag
      .with_published_profile
      .belongs_to_category(params[:category_id])
      .translated_in_current_language_and_not_translated(I18n.locale)
      .pluck(:name)

    Profile
      .with_attached_image
      .is_published
      .by_region(current_region)
      .includes(:taggings, :translations, :topics)
      .where(tags: { name: tag_names })
      .page(params[:page])
      .per(24)
  end

  def profiles_for_search
    Profile
      .with_attached_image
      .is_published
      .by_region(current_region)
      .includes(:taggings, :translations)
      .search(
        params[:search],
        current_region,
        params[:filter_countries],
        params[:filter_states],
        params[:filter_cities],
        params[:filter_lang],
        (!Rails.env.production? || params[:explain]) == true
      )
      .page(params[:page]).per(24)
      .records
  end

  def profiles_with_tags
    Profile
      .is_published
      .by_region(current_region)
      .has_tags(@tags)
      .page(params[:page]).per(24)
  end

  def profiles_for_index
    Profile
      .with_attached_image
      .is_published
      .by_region(current_region)
      .includes(:translations)
      .main_topic_translated_in(I18n.locale)
      .random
      .page(params[:page])
      .per(24)
  end
end
