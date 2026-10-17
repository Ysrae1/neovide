# Neovide Glow Preview

基于 [neovide/neovide](https://github.com/neovide/neovide) 的实验分支 `glow-preview`，加入可调节的柔光效果。保留上游 MIT 许可证。这是第三方分支，尚未合入官方版本；此仓库没有提供经过签名、公证的安装包。

## 配置

此分支默认开启柔光。在 Neovim 配置中可以实时调整：

```lua
if vim.g.neovide then
  vim.g.neovide_bloom = true
  vim.g.neovide_bloom_strength = 0.20
  vim.g.neovide_bloom_radius = 8.0
  vim.g.neovide_bloom_brightness = 1.10
  vim.g.neovide_bloom_saturation = 0.15
end
```

| 参数 | 默认值 | 范围 | 作用 |
| --- | --- | --- | --- |
| `neovide_bloom` | `true` | 布尔值 | 柔光开关 |
| `neovide_bloom_strength` | `0.20` | 0–1 | 线性光能的强度 |
| `neovide_bloom_radius` | `8.0` | 0–32 | 柔光范围，按帧缓冲像素计算；对应高斯模糊的约 3σ |
| `neovide_bloom_brightness` | `1.10` | 0–8 | 柔光层的亮度，独立于范围 |
| `neovide_bloom_saturation` | `0.15` | 0–3 | 彩色柔光的饱和度增强；0 关闭增强，白光保持中性 |

数值会限制在上述范围；强度、范围或亮度为 0 时跳过柔光处理。使用原版 Neovide 时这些新增变量不会提供柔光功能。

柔光从明亮且不同于默认背景色的内容中提取，采用 Skia 原生滤镜，在宽、高各一半的分辨率上模糊，再用 Screen 混合叠加。原始文字与光标保持原分辨率，不经过模糊；叠加的光仍会影响最终感知的亮度和颜色。此实现没有 GPU 到 CPU 的帧回读，不支持直接加载 Ghostty 的 GLSL shader。

## 获取与编译

```sh
git clone --branch glow-preview https://github.com/Ysrae1/neovide.git neovide-glow
cd neovide-glow
git remote add upstream https://github.com/neovide/neovide.git
cargo build --release --locked
./target/release/neovide
```

Rust、Neovim 和系统编译依赖请按仓库现有的[安装说明](website/docs/installation.md)准备。Apple Silicon 也可显式使用原生目标：

```sh
rustup run stable-aarch64-apple-darwin cargo build --release --locked --target aarch64-apple-darwin
./target/aarch64-apple-darwin/release/neovide
```

## 合并官方新功能

`origin` 指向个人 fork，`upstream` 指向官方。`main` 可保持官方历史，日常使用和柔光改动留在 `glow-preview`。下面的操作只更新源码，不替换当前运行的应用：

```sh
git switch glow-preview
git status --short
# 若有未提交改动，先提交或暂存；保持工作区干净后继续。
git fetch upstream --tags
git merge upstream/main
```

合并没有冲突时，官方新功能与柔光提交都会保留。若渲染接口变化导致冲突，先逐项解决并提交合并；需要撤销本次合并时使用 `git merge --abort`。不需要重置分支或强制推送。

完成合并后检查并编译：

```sh
cargo fmt --all -- --check
cargo test --release --locked renderer::bloom_tests
cargo build --release --locked
# 运行编译结果，确认文字、柔光开关和光标动画，再推送。
git push origin glow-preview
```

如果只希望跟随稳定版本，可在 fetch 后把 `upstream/main` 换成已确认的官方版本标签。官方发布不会自动改写此分支；每次合并仍需检查兼容性。建议先验证新构建，再替换已安装的应用，并保留上一版以便恢复。

## 验证与限制

- 本版在 macOS Apple Silicon 上完成 release 编译、CPU 图像断言、Metal 渲染检查，以及实际窗口中的开关验证。
- 默认测试检查原始内容不被压暗、透明像素与独立暗色填充、柔光确实产生以及关闭时跳过处理。测试图形不依赖系统字体。
- Metal 测试需真实 macOS GPU，默认忽略；可用 `cargo test --release --locked renderer::bloom_tests -- --include-ignored` 手动运行。
- Windows、Linux 和其他 GPU 后端尚未验证。实现使用跨平台 Skia 滤镜，但不能据此保证所有后端效果一致。
- 柔光仍有额外渲染开销。降低处理分辨率能减小部分工作量，实际成本随窗口尺寸、GPU、动画频率而变化；本分支没有可用于宣称帧率提升或 GPU 节省比例的正式基准测试。
