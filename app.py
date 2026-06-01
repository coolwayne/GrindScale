from __future__ import annotations

import numpy as np
import streamlit as st
import cv2

from grindscale import (
    BREW_PROFILES,
    COIN_DIAMETER_MM,
    analyze,
    build_recommendation,
    check_capture_quality,
    compute_um_per_px,
    detect_reference_coin_diameter_px,
    draw_particle_overlay,
    make_hist_figure,
)


st.set_page_config(page_title="GrindScale MVP", page_icon="☕", layout="wide")
st.title("☕ GrindScale MVP")
st.caption("拍照分析咖啡顆粒均勻度（本機演算法原型）")

with st.sidebar:
    st.header("分析設定")
    profile_name = st.selectbox("目標器具", list(BREW_PROFILES.keys()), index=0)
    coin_name = st.selectbox("標準參照物", list(COIN_DIAMETER_MM.keys()), index=0)
    use_camera = st.toggle("使用相機拍攝", value=True)
    st.markdown(
        """
拍攝建議：
- 將咖啡粉均勻灑在白紙上
- 避免陽光直射
- 盡量讓畫面只包含樣本區域
"""
    )

image_bytes = None
if use_camera:
    camera_shot = st.camera_input("拍照")
    if camera_shot is not None:
        image_bytes = camera_shot.getvalue()
else:
    uploaded = st.file_uploader("上傳照片", type=["jpg", "jpeg", "png"])
    if uploaded is not None:
        image_bytes = uploaded.read()

if image_bytes is None:
    st.info("請拍照或上傳影像以開始分析。")
    st.stop()

data = np.frombuffer(image_bytes, np.uint8)
image_bgr = cv2.imdecode(data, cv2.IMREAD_COLOR)
if image_bgr is None:
    st.error("影像讀取失敗，請換一張圖片。")
    st.stop()

quality = check_capture_quality(image_bgr)
q_col1, q_col2, q_col3 = st.columns(3)
q_col1.metric("清晰度", f"{quality['blur_score']:.1f}")
q_col2.metric("平均亮度", f"{quality['mean_brightness']:.1f}")
q_col3.metric("前景覆蓋率", f"{quality['occupancy']:.3f}")

if not quality["pass"]:
    st.warning("拍攝品質可能不足，建議重新拍攝以提升穩定性。")

profile = BREW_PROFILES[profile_name]
um_per_px = None
calibration_msg = "相對模式（未校正）"

if coin_name != "None (relative mode)":
    coin_px = detect_reference_coin_diameter_px(image_bgr)
    if coin_px is not None:
        um_per_px = compute_um_per_px(COIN_DIAMETER_MM[coin_name], coin_px)
        calibration_msg = f"校正模式：1 px ≈ {um_per_px:.2f} um（{coin_name}）"
    else:
        st.warning("未偵測到參照硬幣，將改為相對模式。")

output = analyze(image_bgr, profile, um_per_px=um_per_px)
stats = output.stats
recommend = build_recommendation(stats, profile_name)
overlay = draw_particle_overlay(image_bgr, output.particles)
overlay_rgb = cv2.cvtColor(overlay, cv2.COLOR_BGR2RGB)
source_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)

st.subheader("分析結果")
st.caption(calibration_msg)

score_col, count_col, cv_col, mode_col = st.columns(4)
score_col.metric("Uniformity Score", str(stats.uniformity_score))
count_col.metric("顆粒數", str(stats.particle_count))
cv_col.metric("CV", f"{stats.cv:.3f}")
mode_col.metric("模式", "校正" if stats.mode == "calibrated" else "相對")

ratio_col1, ratio_col2, ratio_col3 = st.columns(3)
ratio_col1.metric("細粉比例", f"{stats.fine_ratio * 100:.1f}%")
ratio_col2.metric("目標比例", f"{stats.target_ratio * 100:.1f}%")
ratio_col3.metric("粗粉比例", f"{stats.coarse_ratio * 100:.1f}%")

st.markdown(f"**建議**：{recommend}")

unit = "um" if stats.mode == "calibrated" else "px"
hist = make_hist_figure(output.diameters_for_hist, unit=unit, title="粒徑分佈 Histogram")
st.pyplot(hist, clear_figure=True)

img_col1, img_col2 = st.columns(2)
img_col1.image(source_rgb, caption="原始影像", use_column_width=True)
img_col2.image(overlay_rgb, caption="分類疊圖（藍:細 / 綠:目標 / 紅:粗）", use_column_width=True)
