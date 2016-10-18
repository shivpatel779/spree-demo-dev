module Spree
  module Admin
    class UsersController < ResourceController
      rescue_from Spree::Core::DestroyWithOrdersError, :with => :user_destroy_with_orders_error

      after_action :sign_in_if_change_own_password, only: :update

      # http://spreecommerce.com/blog/2010/11/02/json-hijacking-vulnerability/
      before_action :check_json_authenticity, only: :index

      def index
        respond_with(@collection) do |format|
          format.html
          format.json { render :json => json_data }
        end
      end

      def show
        redirect_to edit_admin_user_path(@user)
      end

      def create
        @user = Spree.user_class.new(user_params)
        if @user.save
          flash.now[:success] = flash_message_for(@user, :successfully_created)
          render :edit
        else
          render :new
        end
      end

      def update
        if params[:user][:password].blank? && params[:user][:password_confirmation].blank?
          params[:user].delete(:password)
          params[:user].delete(:password_confirmation)
        end

        if params[:commit].eql?('Update Personal detail') || params[:commit].eql?('Create Personal detail')
          params.permit!
          if @user.personal_detail.nil?
            personal_detail_params = params[:user].merge!(user_id: @user.id)
            personal_detail = Spree::PersonalDetail.create(personal_detail_params)
          else
            @user.personal_detail.update_attributes(params[:user])
          end
        end

        if params[:commit].eql?('Update Location info') || params[:commit].eql?('Create Location info')
          params.permit!
          if @user.location_info.nil?
            location_params = params[:user].merge!(user_id: params[:id])
            personal_detail = Spree::LocationInfo.create(location_params)
          else
            @user.location_info.update_attributes(params[:user])
          end

        end

        if @user.update_attributes(user_params)
          flash.now[:success] = Spree.t(:account_updated)
        end

        redirect_to edit_admin_user_path(@user)
      end

      def addresses
        if request.put?
          if @user.update_attributes(user_params)
            flash.now[:success] = Spree.t(:account_updated)
          end

          render :addresses
        end
      end

      def orders
        params[:q] ||= {}
        @search = Spree::Order.reverse_chronological.ransack(params[:q].merge(user_id_eq: @user.id))
        @orders = @search.result.page(params[:page]).per(Spree::Config[:admin_products_per_page])
      end

      def items
        params[:q] ||= {}
        @search = Spree::Order.includes(
          line_items: {
            variant: [:product, { option_values: :option_type }]
          }).ransack(params[:q].merge(user_id_eq: @user.id))
        @orders = @search.result.page(params[:page]).per(Spree::Config[:admin_products_per_page])
      end

      def generate_api_key
        if @user.generate_spree_api_key!
          flash[:success] = Spree.t('api.key_generated')
        end
        redirect_to edit_admin_user_path(@user)
      end

      def clear_api_key
        if @user.clear_spree_api_key!
          flash[:success] = Spree.t('api.key_cleared')
        end
        redirect_to edit_admin_user_path(@user)
      end

      def model_class
        Spree.user_class
      end

      protected

        def collection
          return @collection if @collection.present?
          @collection = super
          if request.xhr? && params[:q].present?
            @collection = @collection.includes(:bill_address, :ship_address)
                              .where("spree_users.email #{LIKE} :search
                                     OR (spree_addresses.firstname #{LIKE} :search AND spree_addresses.id = spree_users.bill_address_id)
                                     OR (spree_addresses.lastname  #{LIKE} :search AND spree_addresses.id = spree_users.bill_address_id)
                                     OR (spree_addresses.firstname #{LIKE} :search AND spree_addresses.id = spree_users.ship_address_id)
                                     OR (spree_addresses.lastname  #{LIKE} :search AND spree_addresses.id = spree_users.ship_address_id)",
                                    { :search => "#{params[:q].strip}%" })
                              .limit(params[:limit] || 100)
          else
            @search = @collection.ransack(params[:q])
            @collection = @search.result.page(params[:page]).per(Spree::Config[:admin_products_per_page])
          end
        end

      private

      def user_params
        params.require(:user).permit(permitted_user_attributes |
                                     [spree_role_ids: [],
                                      ship_address_attributes: permitted_address_attributes,
                                      bill_address_attributes: permitted_address_attributes
                                     ])
      end

      # handling raise from Spree::Admin::ResourceController#destroy
      def user_destroy_with_orders_error
        invoke_callbacks(:destroy, :fails)
        render status: :forbidden, text: Spree.t(:error_user_destroy_with_orders)
      end

      # Allow different formats of json data to suit different ajax calls
      def json_data
        json_format = params[:json_format] || 'default'
        case json_format
        when 'basic'
          collection.map { |u| { 'id' => u.id, 'name' => u.email } }.to_json
        else
          address_fields = [:firstname, :lastname, :address1, :address2, :city, :zipcode, :phone, :state_name, :state_id, :country_id]
          includes = { only: address_fields, include: { state: { only: :name }, country: { only: :name } } }

          collection.to_json(only: [:id, :email], include:
                             { bill_address: includes, ship_address: includes })
        end
      end

      def sign_in_if_change_own_password
        if try_spree_current_user == @user && @user.password.present?
          sign_in(@user, event: :authentication, bypass: true)
        end
      end
    end
  end
end