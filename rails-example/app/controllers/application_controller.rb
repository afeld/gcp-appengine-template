require 'digest'

class ApplicationController < ActionController::Base
	# check to make sure we are authenticated before going forward
	before_action :check_auth

	# set the current user depending on whether we are doing basic auth,
	# SSO, or local development
	def current_user
		idp = ENV.fetch('IDP_PROVIDER_URL') {''}
		basicauth_username = ENV.fetch('BASICAUTH_USER') {''}

		if idp != ''
			myuser = request.env['HTTP_X_FORWARDED_USER']
			if myuser.nil?
				logger.info 'missing HTTP_X_FORWARDED_USER: setting to anonymous'
				myuser = 'Anonymous'
			else
				logger.info "using HTTP_X_FORWARDED_USER from proxy: " + myuser
			end
		elsif basicauth_username != ''
			myuser = basicauth_username
			logger.info "setting username to BASICAUTH_USER: " + myuser
		else
			myuser = 'Anonymous'
			logger.info "no username set, using " + myuser
		end
		@current_user ||= myuser
	end
	helper_method :current_user

	# set basic auth if requested, and if we are not using SSO
	pw = ENV.fetch('BASICAUTH_PASSWORD') {''}
	idp = ENV.fetch('IDP_PROVIDER_URL') {''}
	basicauth_username = ENV.fetch('BASICAUTH_USER') {''}
	if pw != '' && idp == '' then
		logger.info "setting basic auth password for " + basicauth_username
		http_basic_authenticate_with name: basicauth_username, password: pw
	end

	private

	def check_auth
		# if we don't have a signature key, then
		# we are running locally and should thus let them in
		signature_key = ENV.fetch('SIGNATURE_KEY') {''}
		return if signature_key == ''

		# If we don't have an IDP set, then we are not doing SSO,
		# and thus should let them in.
		idp = ENV.fetch('IDP_PROVIDER_URL') {''}
		return if idp == ''

		# If we have a properly signed ZAP-Authorization header, then
		# it's the ZAP proxy, and we should let it in
		if ! request.headers['ZAP-Authorization'].nil?
			authheader = request.headers['ZAP-Authorization']
			token, signedtoken = authheader.split(':',2)
			targetversion, datestamp = token.split(':',2)
			if (Time.new.to_i - datestamp).abs > 1800
				logger.info 'ZAP-Authorization has expired'
				render plain: "305 use proxy", status: 305
			end

			checktoken = signature_key + '_' + token
			if Digest::SHA256.hexdigest checktoken == signedtoken
				return
			else
				logger.info 'ZAP-Authorization did not verify'
				render plain: "305 use proxy", status: 305
			end
		end

		# Otherwise, check the HMAC signature
		if request.headers['GAP-Signature'].nil? 
			logger.info 'missing GAP-Signature'
			render plain: "305 use proxy", status: 305
		end
		if ApiAuth.authentic?(request, signature_key, :digest => 'sha1')
			logger.info 'GAP-Signature did not verify'
			render plain: "305 use proxy", status: 305
		end
	end
end
