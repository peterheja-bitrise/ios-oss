@testable import KsApi
@testable import Library
import Prelude
import XCTest

final class OptimizelyClientTypeTests: TestCase {
  func testVariantForExperiment_NoError() {
    let mockClient = MockOptimizelyClient()
      |> \.experiments .~
      [OptimizelyExperiment.Key.pledgeCTACopy.rawValue: OptimizelyExperiment.Variant.variant1.rawValue]

    XCTAssertEqual(
      OptimizelyExperiment.Variant.variant1,
      mockClient.variant(for: .pledgeCTACopy),
      "Returns the correction variation"
    )
    XCTAssertTrue(mockClient.activatePathCalled)
    XCTAssertFalse(mockClient.getVariantPathCalled)
  }

  func testVariantForExperiment_ThrowsError() {
    let mockClient = MockOptimizelyClient()
      |> \.experiments .~
      [OptimizelyExperiment.Key.pledgeCTACopy.rawValue: OptimizelyExperiment.Variant.variant1.rawValue]
      |> \.error .~ MockOptimizelyError.generic

    XCTAssertEqual(
      OptimizelyExperiment.Variant.control,
      mockClient.variant(for: .pledgeCTACopy),
      "Returns the control variant if error is thrown"
    )
    XCTAssertTrue(mockClient.activatePathCalled)
    XCTAssertFalse(mockClient.getVariantPathCalled)
  }

  func testVariantForExperiment_ExperimentNotFound() {
    let mockClient = MockOptimizelyClient()

    XCTAssertEqual(
      OptimizelyExperiment.Variant.control,
      mockClient.variant(for: .pledgeCTACopy),
      "Returns the control variant if experiment key is not found"
    )
    XCTAssertTrue(mockClient.activatePathCalled)
    XCTAssertFalse(mockClient.getVariantPathCalled)
  }

  func testVariantForExperiment_UnknownVariant() {
    let mockClient = MockOptimizelyClient()
      |> \.experiments .~
      [OptimizelyExperiment.Key.pledgeCTACopy.rawValue: "other_variant"]

    XCTAssertEqual(
      OptimizelyExperiment.Variant.control,
      mockClient.variant(for: .pledgeCTACopy),
      "Returns the control variant if the variant is not recognized"
    )
    XCTAssertTrue(mockClient.activatePathCalled)
    XCTAssertFalse(mockClient.getVariantPathCalled)
  }

  func testVariantForExperiment_NoError_LoggedIn_IsAdmin() {
    let mockClient = MockOptimizelyClient()
      |> \.experiments .~
      [OptimizelyExperiment.Key.pledgeCTACopy.rawValue: OptimizelyExperiment.Variant.variant1.rawValue]

    let user = User.template |> User.lens.isAdmin .~ true

    withEnvironment(currentUser: user) {
      XCTAssertEqual(
        OptimizelyExperiment.Variant.variant1,
        mockClient.variant(for: .pledgeCTACopy),
        "Returns the correction variation"
      )
      XCTAssertFalse(mockClient.activatePathCalled)
      XCTAssertTrue(mockClient.getVariantPathCalled)
    }
  }

  func testGetVariation() {
    let mockOptimizelyClient = MockOptimizelyClient()
      |> \.experiments .~
      [OptimizelyExperiment.Key.pledgeCTACopy.rawValue: OptimizelyExperiment.Variant.variant1.rawValue]

    withEnvironment(currentUser: User.template, optimizelyClient: mockOptimizelyClient) {
      let variation = mockOptimizelyClient.getVariation(for: .pledgeCTACopy)
      let userAttributes = mockOptimizelyClient.userAttributes

      XCTAssertEqual(.variant1, variation)
      XCTAssertTrue(mockOptimizelyClient.getVariantPathCalled)

      assertUserAttributes(userAttributes)
    }
  }

  func testGetVariation_Error() {
    let mockOptimizelyClient = MockOptimizelyClient()
      |> \.experiments .~
      [OptimizelyExperiment.Key.pledgeCTACopy.rawValue: OptimizelyExperiment.Variant.variant1.rawValue]

    withEnvironment(currentUser: User.template, optimizelyClient: mockOptimizelyClient) {
      let variation = mockOptimizelyClient.getVariation(for: .nativeMeProjectSummary)
      let userAttributes = mockOptimizelyClient.userAttributes

      XCTAssertEqual(.control, variation, "Defaults to control when error is thrown")
      XCTAssertTrue(mockOptimizelyClient.getVariantPathCalled)

      assertUserAttributes(userAttributes)
    }
  }

  func testOptimizelyProperties_Production() {
    let mockOptimizelyClient = MockOptimizelyClient()
      |> \.experiments .~ [
        OptimizelyExperiment.Key.nativeOnboarding.rawValue:
          OptimizelyExperiment.Variant.control.rawValue,
        OptimizelyExperiment.Key.nativeMeProjectSummary.rawValue:
          OptimizelyExperiment.Variant.variant1.rawValue,
        OptimizelyExperiment.Key.nativeProjectPageCampaignDetails.rawValue:
          OptimizelyExperiment.Variant.variant2.rawValue
      ]
      |> \.allKnownExperiments .~ [
        OptimizelyExperiment.Key.nativeOnboarding,
        OptimizelyExperiment.Key.nativeMeProjectSummary,
        OptimizelyExperiment.Key.nativeProjectPageCampaignDetails,
        OptimizelyExperiment.Key.onboardingCategoryPersonalizationFlow
      ]
    let mockService = MockService(serverConfig: ServerConfig.staging)

    withEnvironment(apiService: mockService, optimizelyClient: mockOptimizelyClient) {
      let properties = optimizelyProperties()
      let optimizelyExperiments = properties?["optimizely_experiments"] as? [[String: String]]

      XCTAssertEqual("Staging", properties?["optimizely_environment"] as? String)
      XCTAssertEqual(Secrets.OptimizelySDKKey.staging, properties?["optimizely_api_key"] as? String)
      XCTAssertEqual([
        [
          "optimizely_experiment_slug": "native_onboarding_series_new_backers",
          "optimizely_variant_id": "control"
        ],
        [
          "optimizely_experiment_slug": "native_me_project_summary",
          "optimizely_variant_id": "variant-1"
        ],
        [
          "optimizely_experiment_slug": "native_project_page_campaign_details",
          "optimizely_variant_id": "variant-2"
        ],
        [
          "optimizely_experiment_slug": "onboarding_category_personalization_flow",
          "optimizely_variant_id": "unknown" // Not found in experiments
        ]
      ], optimizelyExperiments)

      XCTAssertEqual(4, optimizelyExperiments?.count)
    }
  }

  private func assertUserAttributes(_ userAttributes: [String: Any?]?) {
    XCTAssertEqual("us", userAttributes?["user_country"] as? String)
    XCTAssertEqual("en", userAttributes?["user_display_language"] as? String)
    XCTAssertEqual("MockSystemVersion", userAttributes?["session_os_version"] as? String)
    XCTAssertEqual("1.2.3.4.5.6.7.8.9.0", userAttributes?["session_app_release_version"] as? String)
    XCTAssertEqual(true, userAttributes?["session_apple_pay_device"] as? Bool)
    XCTAssertEqual("phone", userAttributes?["session_device_format"] as? String)
    XCTAssertEqual(true, userAttributes?["session_user_is_logged_in"] as? Bool)

    XCTAssertNil(userAttributes?["user_facebook_account"] as? Bool)
    XCTAssertNil(userAttributes?["user_backed_projects_count"] as? Int)
    XCTAssertNil(userAttributes?["user_launched_projects_count"] as? Int)
    XCTAssertNil(userAttributes?["user_distinct_id"] as? String)
    XCTAssertNil(userAttributes?["session_referrer_credit"] as? String)
    XCTAssertNil(userAttributes?["session_ref_tag"] as? String)
  }
}
