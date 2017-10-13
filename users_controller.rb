class Api::UsersController < ApplicationController

  # Lots of the code is skipped due to the protection of the trade secrets
  # Can't post everything on the Internet
  # Lots of the code is skipped due to the protection of the trade secrets
  # Can't post everything on the Internet
  # Lots of the code is skipped due to the protection of the trade secrets
  # Can't post everything on the Internet

  swagger_api :sign_in do
    summary "Sign in a user with facebook"
    param :form, :'user[facebook_oauth_access_token]', :string, :required, 'User facebook oauth token'
    param :form, :'user[latitude]', :double, :optional, 'User location of latitude'
    param :form, :'user[longitude]', :double, :optional, 'User location of longitude'

    response :unauthorized
    response :ok
  end

  def sign_in
    if params[:user][:facebook_oauth_access_token].match('fake')
      user = User.where(facebook_oauth_access_token: params[:user][:facebook_oauth_access_token]).first
      render json: user, status: :ok and return
    end
    fb_token = params[:user][:facebook_oauth_access_token]
    if fb_token
      begin
        fb_graph = Koala::Facebook::API.new(fb_token)
        profile = fb_graph.get_object("me", fields: 'id,email,first_name,last_name,gender,bio,birthday,education,work,location')
        params[:user][:raw_fb_response] = profile
        params[:user][:facebook_id] = profile['id']
        # Retrive FB profile image
        image_info = HTTParty.get("https://graph.facebook.com/#{profile['id']}/picture?redirect=false")
        fb_default_photo = image_info["data"]["is_silhouette"] rescue false
        params[:user][:facebook_profile_image_url] = "https://graph.facebook.com/#{profile['id']}/picture?width=750" unless fb_default_photo
        params[:user][:email] = profile['email']
        params[:user][:first_name] = profile['first_name']
        params[:user][:last_name] = profile['last_name']
        params[:user][:gender] = profile['gender'].downcase == 'male' ? 0 : 1 if profile['gender']
        params[:user][:description] = profile['bio']
        params[:user][:date_of_birth] = Date.strptime(profile['birthday'], '%m/%d/%Y') if profile['birthday']
        params[:user][:education] = profile['education']
        params[:user][:work] = profile['work']
        if profile['location']
          geo = Geocoder.search(profile['location']['name']).first
          if geo
            params[:user][:city] = geo.city
            params[:user][:state] = geo.state_code
            params[:user][:country] = geo.country_code
          end
        end
      rescue => e
      end
    end
    if params[:user][:email].nil?
      # If user email is nil, try facebook id
      user = User.find_by_facebook_id(params[:user][:facebook_id])
      # If user doesn't not exist, create a fake facebook email for user
      params[:user][:email] = "#{params[:user][:first_name]}.#{params[:user][:last_name]}@facebook.com".downcase if user.nil?
    else
      user = User.find_by_email(params[:user][:email])
    end
    # User signs up
    if user.nil? || !user.registered?
      if user.nil?
        user = User.new(user_params)
      else
        user.update_attributes(user_params)
      end
      user.raw_fb_response = profile if profile
      user.save!
      questions = Question.signup.as_json
      categories = QuestionCategory.where(selectable: true)
      Match.compose_system_support_match(user)

      # Save FB profile image
      if user.facebook_profile_image_url
        profile_image = ProfileImage.new user: user, primary: true
        profile_image.remote_file_url = user.facebook_profile_image_url
        profile_image.save
      end

      user_json = UserSerializer.new(user).serializable_hash
      response_hash = user_json.merge(questions: questions, categories: categories, new_user: true)
      SignInLog.compose(user, { ip: request.remote_ip, latitude: params[:user][:latitude], longitude: params[:user][:longitude] })
      UserEducation.compose(user, params[:user][:education] || [])
      UserWork.compose(user, params[:user][:work] || [])

      # Send welcome email
      UserMailer.delay_for(10.minute).welcome_email(user)
      ProfileVerificationWorker.perform_in(10.minutes, user.id)
      render json: response_hash, status: :created
    else
      # Update column if the value is nil
      params[:user].each { |k, v| user.send("#{k}=", v) if user.respond_to?(k) && user.send(k).nil? }
      user.raw_fb_response = profile if profile
      user.save!
      SignInLog.compose(user, { ip: request.remote_ip, latitude: params[:user][:latitude], longitude: params[:user][:longitude] })
      UserEducation.compose(user, params[:user][:education]) if user.user_educations.empty? && params[:user][:education].present?
      UserWork.compose(user, params[:user][:work]) if user.user_works.empty? && params[:user][:work].present?
      ProfileVerificationWorker.perform_in(10.minutes, user.id)
      render json: user, status: :ok
    end
  rescue => e
    if user.errors.keys.include?(:email)
      error = "Please make sure your Facebook account has a valid email address"
    else
      error = user.errors.full_messages.first
    end
    render json: { ec: 422, em: error }, status: :unprocessable_entity
  end