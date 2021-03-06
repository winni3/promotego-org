class SearchController < ApplicationController
  def radius
    set_display_variables

    if(@address)
      db_results = Location.find(:all, find_params)

      if (db_results.blank?)
        find_closest
      else
        db_results.sort! do |a,b|
          if a.city == b.city && a.state == b.state && a.geocode_precision != b.geocode_precision
            if a.geocode_precision == "address"
              -1
            else
              1
            end
          else
            a.distance.to_f <=> b.distance.to_f
          end
        end

        @results = process_location_headings(db_results)
      end

      if @results.blank? && @closest.blank?
        flash.now[:error] = "No locations matched your search within 100 miles"
      end
    end
  end

  private
  def set_display_variables
    @address = params[:address]
    session[:last_search_address] = @address
    @radius = params[:radius].to_d if params[:radius]

    if params[:type]
      @type = Type.find_by_name(params[:type].gsub(/_/, ' ').singularize.titleize)
      if @type
        @type_id = @type.id
      end
    elsif params[:type_id]
      @type_id = params[:type_id].to_d if params[:type_id]
    end

    @radii = [5,10,25,50,100]
    @types = Type.find(:all)
  end

  def find_params
    returning Hash.new do |find_params|
      find_params.merge!({:origin => @address, :within => @radius,
        :order => :distance})
      if @type_id && @type_id > 0
        find_params[:conditions] = ['type_id = ?', @type_id]
      end
    end
  end

  def find_closest
    closest_params = {:origin => @address, :within => 100}
    if (@type_id && @type_id > 0)
      closest_params[:conditions] = ['lat is not null and lng is not null and type_id = ?', @type_id]
    else
      closest_params[:conditions] = 'lat is not null and lng is not null'
    end

    @closest = Location.find_closest(closest_params)
  end

  def process_location_headings(results)
    returning [] do |retval|
      current_heading = nil
      current_distances = []
      current_city_distance = nil

      results.each do |result|
        heading = location_heading(result)

        if current_heading
          unless current_heading.geocode_address == heading
            # current heading doesn't match
            # compute average distance or city distance
            if current_city_distance
              current_heading.distance = current_city_distance
            else
              current_heading.distance = (current_distances.inject(0){|sum,current| sum + current}/current_distances.size).to_s
            end

            # erase distances
            current_distances = []
            current_city_distance = nil

            # create new heading
            current_heading = Location::LocationHeader.new(heading, :city)
            retval << current_heading
          end
        else
          current_heading = Location::LocationHeader.new(heading, :city)
          retval << current_heading
        end

        if result.geocode_precision == "address"
          current_distances << result.distance.to_f
        else
          current_city_distance ||= result.distance
        end

        retval << result
      end

      # compute average distance or city distance
      if current_city_distance
        current_heading.distance = current_city_distance
      else
        current_heading.distance = (current_distances.inject(0){|sum,current| sum + current}/current_distances.size).to_s
      end
    end
  end

  def location_heading(location)
    components = []

    if !location.city.blank?
      components << location.city
    elsif !location.zip_code.blank?
      components << location.zip_code
    end

    components << location.state unless location.state.blank?

    return components.join(', ') if components.length == 2

    components << location.country unless location.country.blank?

    return components.join(', ')
  end
end
