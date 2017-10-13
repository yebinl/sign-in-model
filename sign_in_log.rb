class SignInLog < ActiveRecord::Base
  belongs_to :user

  geocoded_by :ip do |obj, results|
    if geo = results.first
      obj.city = geo.city if geo.city.present?
      obj.state = geo.state_code if geo.state_code.present?
      obj.country = geo.country_code if geo.country_code.present?
      if geo.latitude.present? && geo.longitude.present?
        obj.latitude = geo.latitude unless geo.latitude.to_f == 0.0
        obj.longitude = geo.longitude unless geo.longitude.to_f == 0.0
      end
      obj.zipcode = geo.postal_code if geo.postal_code.present?
    end
  end

  reverse_geocoded_by :latitude, :longitude do |obj, results|
    if geo = results.first
      if geo.city.present?
        obj.city = geo.city
        obj.user.city = geo.city if obj.user.city.nil?
      end
      if geo.state_code.present?
        obj.state = geo.state_code
        obj.user.state = geo.state_code if obj.user.state.nil?
      end
      if geo.country_code.present?
        obj.country = geo.country_code
        obj.user.country = geo.country_code if obj.user.country.nil?
      end
      obj.user.save
      if geo.postal_code.present?
        obj.zipcode = geo.postal_code
      end
    end
  end

  after_validation :geocode, if: ->(obj) { obj.ip_changed? && (!obj.latitude || !obj.longitude) }
  after_validation :reverse_geocode, if: ->(obj) { obj.latitude_changed? || obj.longitude_changed? }

  def self.compose(user, options = {})
    log = SignInLog.new
    log.user = user
    log.ip = options[:ip] unless options[:ip].nil?
    log.latitude = options[:latitude] unless options[:latitude].nil?
    log.longitude = options[:longitude] unless options[:longitude].nil?
    log.meta_data = options.slice(:user_agent) if options[:user_agent]
    log.save unless log.ip.nil? && log.latitude.nil? && log.longitude.nil?
  rescue
  end
end
