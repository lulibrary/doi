require 'test_helper'

class DoisControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get search" do
    get :search
    assert_response :success
  end

  test "should get reservations" do
    get :reservations
    assert_response :success
  end

  # test "should find" do
  #   post :find, {pure_id: 74562}
  #   assert_response :success
  # end

end
