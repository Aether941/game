// =============================================================================
// invert-date-text.shader  --  时间文本按背景画面自动反色
// 适用: OBS Studio 32.x + obs-shaderfilter 2.6.0 (Exeldro)
//
// 思路
//   这个滤镜加在「时间文本」那个浏览器源上。着色器只拿到文本源的贴图:
//   白色文字 + 透明背景。所以我们把「背景源」当作第二个贴图参数传进来,
//   用同一个 uv 去采样背景贴图, 用背景像素算出反色, 只画在文字的像素上
//   (非文字像素 alpha=0, 输出透明, 真实背景照常透出来)。
//
// 使用方法
//   1. 时间文本源建议设成和画布一样大(如 1920x1080), 位置 (0,0), 缩放 1.0,
//      文字用 HTML/CSS 摆位。这样两个贴图的 uv 天然 1:1 对齐, 无需调参。
//   2. 时间源 → 滤镜 → 加「User-defined shader / 用户自定义着色器」
//      → 勾选"从文件加载着色器文本" → 选择本文件。
//   3. 在滤镜属性里把「背景 Background」绑定成背景画面:
//        下拉框 = 选一个 OBS 源或场景 (可跟随游戏画面实时变化)
//        右侧路径框 = 或者直接选一张背景图片文件
//      ⚠ 千万不要选"包含这个时间源的那个场景", 会自我递归。
//   4. 属性里可以切反色方式 / 强度, 以及在 uv 对不齐时手工微调。
//
// 备注
//   * 本 shader 依赖插件自带的 alpha 处理(插件默认会把输入做 alpha divide),
//     所以 image.rgb 是"未预乘"的原色, 文字像素就是纯白 1,1,1。
//   * 输出默认按插件惯例给"未预乘"颜色; 如果边缘发白发亮, 打开"预乘 Alpha"。
// =============================================================================

uniform string usage_info<
    string label = "说明";
    string widget_type = "info";
> = "把下面的[背景]绑定到背景源(或一张背景图片)。文字所在源建议设为画布大小、位置(0,0)、缩放1.0,uv 才能自动对齐;不是全画布时用[4.对齐]里的参数微调。";

// ---------------------------------------------------------------------------
// 1. 背景贴图: 下拉选源/场景, 或右边选图片文件
// ---------------------------------------------------------------------------
uniform texture2d background<
    string label = "背景 (Background)";
    string group = "1. 背景";
>;

// ---------------------------------------------------------------------------
// 2. 反色方式
// ---------------------------------------------------------------------------
uniform int invert_mode<
    string label = "反色方式";
    string group = "2. 反色";
    string widget_type = "select";
    int option_0_value = 0;
    string option_0_label = "反相 (1 - 背景色)";
    int option_1_value = 1;
    string option_1_label = "按亮度取黑/白 (更易读)";
> = 0;

uniform float invert_amount<
    string label = "反色强度";
    string group = "2. 反色";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 1.0;
    float step = 0.01;
> = 1.0;

uniform float threshold<
    string label = "亮度阈值";
    string group = "2. 反色";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 1.0;
    float step = 0.01;
> = 0.5;

// ---------------------------------------------------------------------------
// 3. 输出
// ---------------------------------------------------------------------------
uniform bool premultiply_alpha<
    string label = "预乘 Alpha (边缘发白时打开)";
    string group = "3. 输出";
> = false;

// ---------------------------------------------------------------------------
// 4. 对齐微调 (两个贴图 uv 对不齐时才需要动)
//    背景 uv = 文本 uv * 缩放 + 偏移
//    例: 文字源 960x540 放在画布 (960,540) 处, 画布 1920x1080
//        → 缩放 x/y = 0.5, 偏移 x/y = 50 (%)
// ---------------------------------------------------------------------------
uniform float bg_scale_x<
    string label = "背景 UV 缩放 X";
    string group = "4. 对齐";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 4.0;
    float step = 0.001;
> = 1.0;

uniform float bg_scale_y<
    string label = "背景 UV 缩放 Y";
    string group = "4. 对齐";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 4.0;
    float step = 0.001;
> = 1.0;

uniform float bg_offset_x<
    string label = "背景 UV 偏移 X (%)";
    string group = "4. 对齐";
    string widget_type = "slider";
    float minimum = -200.0;
    float maximum = 200.0;
    float step = 0.1;
> = 0.0;

uniform float bg_offset_y<
    string label = "背景 UV 偏移 Y (%)";
    string group = "4. 对齐";
    string widget_type = "slider";
    float minimum = -200.0;
    float maximum = 200.0;
    float step = 0.1;
> = 0.0;

// ---------------------------------------------------------------------------

float4 mainImage(VertData v_in) : TARGET
{
    // 文字贴图: 白色文字, 文字外 alpha = 0
    float4 text = image.Sample(textureSampler, v_in.uv);

    // 采样背景贴图 (默认与文字贴图 1:1 对齐)
    float2 bg_uv = v_in.uv * float2(bg_scale_x, bg_scale_y)
                 + float2(bg_offset_x, bg_offset_y) * 0.01;
    float4 bg = background.Sample(textureSampler, bg_uv);

    // 算出这块背景对应的"反色"
    float3 inverted;
    if (invert_mode == 1) {
        // 按亮度二选一: 背景亮 → 黑字, 背景暗 → 白字
        float luma = dot(bg.rgb, float3(0.2126, 0.7152, 0.0722));
        inverted = (luma > threshold) ? float3(0.0, 0.0, 0.0) : float3(1.0, 1.0, 1.0);
    } else {
        // 直接反相(等于和背景做 difference 混合)
        inverted = 1.0 - bg.rgb;
    }

    // 背景透明的地方(没有画面)保持原来的文字颜色
    inverted = lerp(text.rgb, inverted, bg.a);

    // 和原文字颜色按强度混合, alpha 完全沿用文字自身(保住抗锯齿边缘)
    float3 rgb   = lerp(text.rgb, inverted, invert_amount);
    float  alpha = text.a;

    if (premultiply_alpha)
        return float4(rgb * alpha, alpha);

    return float4(rgb, alpha);
}
