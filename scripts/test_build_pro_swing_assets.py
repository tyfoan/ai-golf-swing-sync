import unittest

from scripts import build_pro_swing_assets as builder


class ProSwingAssetCropTests(unittest.TestCase):
    def test_crop_x_uses_bbox_center_and_clamps_to_source_edges(self):
        self.assertEqual(
            builder.crop_x_for_bbox([0.0, 0.0, 0.45, 1.0], scaled_width=1920, crop_width=1620),
            0,
        )
        self.assertEqual(
            builder.crop_x_for_bbox([0.40, 0.0, 0.20, 1.0], scaled_width=1920, crop_width=1620),
            150,
        )
        self.assertEqual(
            builder.crop_x_for_bbox([0.51, 0.0, 0.49, 1.0], scaled_width=1920, crop_width=1620),
            300,
        )

    def test_video_filter_uses_landscape_rectangle_and_bbox_crop(self):
        video_filter = builder.video_filter_for_bbox([0.51, 0.0, 0.49, 1.0])

        self.assertIn("scale=-2:1080", video_filter)
        self.assertIn("crop=1620:1080:300:0", video_filter)


if __name__ == "__main__":
    unittest.main()
