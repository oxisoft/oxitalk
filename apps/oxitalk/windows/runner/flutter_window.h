#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // The property that marks OxiTalk's window, for a second launch to find it.
  static constexpr wchar_t kWindowProperty[] = L"io.oxisoft.oxitalk.window";

  // WM_COPYDATA's dwData for a link (UTF-8) a second launch hands over.
  static constexpr ULONG_PTR kLinkMessage = 0x4F584C4B;  // "OXLK"

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // io.oxisoft.oxitalk/links: takeLink gives Dart the link of the last second launch;
  // linkArrived tells it one came.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      links_channel_;
  std::string pending_link_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
