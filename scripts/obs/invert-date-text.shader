// =============================================================================
// invert-date-text.shader  --  时间文本按"文字后面那一小块背景"反色
// 适用: OBS Studio 32.x + obs-shaderfilter 2.6.0 (Exeldro)
//
// ⚠ 本文件刻意保持【单文件、零 #include】。
//    插件 load_shader_from_file 解析 include 时用 strrchr(file_name, '/') 找目录,
//    而递归调用传进去的是 os_get_abs_path_ptr() 的结果(Windows 上是反斜杠),
//    于是找不到 '/' → 长度算成垃圾值 → bmemdup 崩溃。
//    结论: 被 include 的文件里绝不能再有 #include (只能一层), 否则 OBS 直接崩。
//    要分模式就多复制几份这个单文件, 别用嵌套 include。
//
// 思路
//   滤镜加在「时间文本」那个浏览器源上。着色器只拿到文本源的贴图:
//   白色文字 + 透明背景。我们把「背景源」当第二个贴图参数传进来, 在文字
//   对应的那块背景上取色, 算出反色, 只画在文字的像素上(非文字像素 alpha=0,
//   输出透明, 真实背景照常透出来)。
//
//   ★ 关键一: uv 必须对齐
//   插件把背景源按"它自己的分辨率"渲染成一张贴图, 着色器用 uv 0..1 去采样;
//   而滤镜贴图是"文本源自己的分辨率", 它的 uv 0..1 只覆盖文本源那个矩形。
//   所以默认参数下 0..1 会覆盖【整张背景】, 看起来就像"按整张背景反色"。
//   正确关系:  背景 uv = 文字源 uv * 缩放 + 偏移
//        缩放 = 文字源显示尺寸 / 画布尺寸
//        偏移 = 文字源显示位置 / 画布尺寸
//   → 最省事: 把浏览器源宽高直接设成画布大小(2560x1440), 场景里不缩放、
//     位置 (0,0), 文字位置交给 HTML/CSS。这样 缩放=(1,1)、偏移=(0,0),
//     永远自动对齐, 换场景/挪位置都不会错。
//   → 背景优先绑定【一个只放背景的场景】: 场景源永远按画布尺寸渲染, 且已应用
//     内部所有 item 的变换, 所以它的贴图和画布严格 1:1, 偏移恒为 0;
//     绑定【源】时, 它在场景里必须正好铺满画布, 否则取色会和画面对不上。
//     ⚠ 这个背景场景里绝对不能有文本源本身, 否则自我递归。
//
//   ★ 关键二: 取哪块背景 (采样方式)
//   - 逐像素: 每个文字像素取它正背后的那一点背景 → 零参数, 笔画会随背景变色
//   - 区域平均: 在[采样区]里取平均色, 整段文字同一个颜色 → 更稳、更易读
//     采样区用"相对文字框的百分比"表示, 所以文字框=画布时它就是画布的百分比。
//     例(文字在左下角, 画布 2560x1440): 中心 X=48% Y=88%, 宽=94% 高=18%
//
// 使用方法
//   1. 时间源 → 滤镜 → 加「User-defined shader / 用户自定义着色器」
//      → 勾选"从文件加载着色器文本" → 选择本文件 (改完文件点 Reload effect)。
//   2. 属性里把「背景 Background」绑定成背景画面:
//        下拉框 = 选一个 OBS 源或场景 (可跟随游戏画面实时变化)
//        右侧路径框 = 或者直接选一张背景图片文件
//      ⚠ 千万不要选"包含这个时间源的那个场景", 会自我递归。
//      ⚠ 绑定的是源时: 它在场景里必须正好 1:1 铺满画布。
//   3. 对齐(见关键一), 然后挑采样方式与反色方式。
//
// 备注
//   * 本 shader 依赖插件自带的 alpha 处理(插件默认把输入做 alpha divide),
//     所以 image.rgb 是"未预乘"的原色, 文字像素就是纯白 1,1,1。
//   * 输出默认按插件惯例给"未预乘"颜色; 如果边缘发白发亮, 打开"预乘 Alpha"。
// =============================================================================

uniform string usage_info<
    string label = "说明";
    string widget_type = "info";
> = "1) [背景]绑定背景源或图片(推荐绑一个只放背景的场景, 它按画布尺寸渲染, uv 永远 1:1)。2) 文字源若就是画布大小, [5.对齐]保持 1/1/0/0; 否则填 缩放=文字源显示尺寸/画布, 偏移=文字源位置/画布。3) [2.采样]默认区域平均(整段同色), 用[采样区]圈出文字后面那块背景; 想零参数就选'逐像素'。4) 标了(仅[X] 用)的参数只在你选了 X 那个方式时才起作用。";

// ---------------------------------------------------------------------------
// 1. 背景贴图: 下拉选源/场景, 或右边选图片文件
// ---------------------------------------------------------------------------
uniform texture2d background<
    string label = "背景 (Background)";
    string group = "1. 背景";
>;

// ---------------------------------------------------------------------------
// 2. 采样: 看哪块背景、怎么取色
// ---------------------------------------------------------------------------
uniform int sample_mode<
    string label = "采样方式";
    string group = "2. 采样";
    string widget_type = "select";
    int option_0_value = 0;
    string option_0_label = "逐像素: 每个文字像素取正背后的点 (零参数)";
    int option_1_value = 1;
    string option_1_label = "区域平均: 取采样区平均色 (整段同色)";
> = 1;

// 采样区: 相对"文字框"的百分比。文字框=画布时, 百分比就是画布的百分比。
// 默认 50/50/100/100 = 整个文字框。
uniform float patch_center_x<
    string label = "采样区中心 X (%) (仅[区域平均] 用)";
    string group = "2. 采样";
    string widget_type = "slider";
    float minimum = -50.0;
    float maximum = 150.0;
    float step = 0.5;
> = 50.0;

uniform float patch_center_y<
    string label = "采样区中心 Y (%) (仅[区域平均] 用)";
    string group = "2. 采样";
    string widget_type = "slider";
    float minimum = -50.0;
    float maximum = 150.0;
    float step = 0.5;
> = 50.0;

uniform float patch_width<
    string label = "采样区宽 (%) (仅[区域平均] 用)";
    string group = "2. 采样";
    string widget_type = "slider";
    float minimum = 1.0;
    float maximum = 200.0;
    float step = 0.5;
> = 100.0;

uniform float patch_height<
    string label = "采样区高 (%) (仅[区域平均] 用)";
    string group = "2. 采样";
    string widget_type = "slider";
    float minimum = 1.0;
    float maximum = 200.0;
    float step = 0.5;
> = 100.0;

uniform int average_samples<
    string label = "平均采样网格 N×N (仅[区域平均] 用)";
    string group = "2. 采样";
    string widget_type = "slider";
    int minimum = 2;
    int maximum = 16;
    int step = 1;
> = 8;

// ---------------------------------------------------------------------------
// 3. 反色方式
// ---------------------------------------------------------------------------
uniform int invert_mode<
    string label = "反色方式";
    string group = "3. 反色";
    string widget_type = "select";
    int option_0_value = 0;
    string option_0_label = "反相 (1 - 背景色)";
    int option_1_value = 1;
    string option_1_label = "按亮度取黑/白 (更易读)";
    int option_2_value = 2;
    string option_2_label = "偏移反相/异或 (I ^ n)";
> = 0;

uniform int xor_value<
    string label = "异或值 n (仅[偏移反相/异或] 用)";
    string group = "3. 反色";
    string widget_type = "slider";
    int minimum = 0;
    int maximum = 255;
    int step = 1;
> = 128;

uniform float invert_amount<
    string label = "反色强度";
    string group = "3. 反色";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 1.0;
    float step = 0.01;
> = 1.0;

uniform float threshold<
    string label = "亮度阈值 (仅[按亮度取黑/白] 用)";
    string group = "3. 反色";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 1.0;
    float step = 0.01;
> = 0.5;

// ---------------------------------------------------------------------------
// 4. 输出
// ---------------------------------------------------------------------------
uniform bool premultiply_alpha<
    string label = "预乘 Alpha (边缘发白时打开)";
    string group = "4. 输出";
> = false;

// ---------------------------------------------------------------------------
// 5. 对齐: 背景 uv = 文字源 uv * 缩放 + 偏移
//    例: 640x64 的源被拉到 2560x256 放在 (0,0), 画布 2560x1440
//        → 缩放 (1.0, 0.1778), 偏移 (0, 0)
//    例: 源 640x64 不缩放放在 (1000, 1300), 画布 2560x1440
//        → 缩放 (0.25, 0.0444), 偏移 (39.06(%), 90.28(%))
// ---------------------------------------------------------------------------
uniform float bg_scale_x<
    string label = "背景 UV 缩放 X";
    string group = "5. 对齐";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 4.0;
    float step = 0.001;
> = 1.0;

uniform float bg_scale_y<
    string label = "背景 UV 缩放 Y";
    string group = "5. 对齐";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 4.0;
    float step = 0.001;
> = 1.0;

uniform float bg_offset_x<
    string label = "背景 UV 偏移 X (%)";
    string group = "5. 对齐";
    string widget_type = "slider";
    float minimum = -200.0;
    float maximum = 200.0;
    float step = 0.1;
> = 0.0;

uniform float bg_offset_y<
    string label = "背景 UV 偏移 Y (%)";
    string group = "5. 对齐";
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

    // 文字框在背景贴图里对应的矩形
    float2 box_origin = float2(bg_offset_x, bg_offset_y) * 0.01;
    float2 box_span   = float2(bg_scale_x, bg_scale_y);

    float3 bg_rgb;
    float  bg_alpha;

    if (sample_mode == 1) {
        // 采样区 = 文字框内的一块矩形(百分比), 默认就是整个文字框
        float2 patch_origin = box_origin
                            + box_span * (float2(patch_center_x, patch_center_y) * 0.01)
                            - box_span * (float2(patch_width, patch_height) * 0.005);
        float2 patch_span   = box_span * (float2(patch_width, patch_height) * 0.01);

        // N x N 网格取平均(按 alpha 加权), 整段文字用同一个颜色
        int n = clamp(average_samples, 2, 16);
        float3 sum   = float3(0.0, 0.0, 0.0);
        float  sum_a = 0.0;
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                float2 t = (float2(i, j) + 0.5) / float(n);
                float4 s = background.Sample(textureSampler, patch_origin + t * patch_span);
                sum   += s.rgb * s.a;
                sum_a += s.a;
            }
        }
        bg_rgb   = (sum_a > 0.0) ? sum / sum_a : float3(0.0, 0.0, 0.0);
        bg_alpha = sum_a / float(n * n);
    } else {
        // 逐像素: 每个文字像素取它正背后那一点背景
        float4 s = background.Sample(textureSampler, v_in.uv * box_span + box_origin);
        bg_rgb   = s.rgb;
        bg_alpha = s.a;
    }

    // 算出对应背景的"反色"
    float3 inverted;
    if (invert_mode == 1) {
        // 按亮度二选一: 背景亮 → 黑字, 背景暗 → 白字
        float luma = dot(bg_rgb, float3(0.2126, 0.7152, 0.0722));
        inverted = (luma > threshold) ? float3(0.0, 0.0, 0.0) : float3(1.0, 1.0, 1.0);
    } else if (invert_mode == 2) {
        // 偏移反相/异或: I' = I ^ n, R/G/B 各通道独立做 (n = [异或值])
        // n = 128 时就是 (I + 128) mod 256 (翻转最高位):
        //   0→128, 64→192, 128→0, 255→127
        // 注意: 异或 与 "加 n 再取模 256" 只在 n 是 2 的幂时相同。
        uint3 c = (uint3)(saturate(bg_rgb) * 255.0 + 0.5);
        c ^= (uint)clamp(xor_value, 0, 255);
        inverted = (float3)c * (1.0 / 255.0);
    } else {
        // 直接反相(等于和背景做 difference 混合)
        inverted = 1.0 - bg_rgb;
    }

    // 背景透明的地方(没有画面)保持原来的文字颜色
    inverted = lerp(text.rgb, inverted, bg_alpha);

    // 和原文字颜色按强度混合, alpha 完全沿用文字自身(保住抗锯齿边缘)
    float3 rgb   = lerp(text.rgb, inverted, invert_amount);
    float  alpha = text.a;

    if (premultiply_alpha)
        return float4(rgb * alpha, alpha);

    return float4(rgb, alpha);
}
