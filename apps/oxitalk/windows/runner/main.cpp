#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#pragma comment(lib, "advapi32.lib")

#include <cwctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// One OxiTalk per user session: one engine on one Matrix store.
constexpr wchar_t kInstanceMutex[] = L"Local\\io.oxisoft.oxitalk";

constexpr wchar_t kSchemeKey[] = L"Software\\Classes\\matrix";
constexpr wchar_t kCommandKey[] =
    L"Software\\Classes\\matrix\\shell\\open\\command";

// Whether |arg| is a link OxiTalk opens (see lib/src/app/matrix_link.dart).
bool IsMatrixLink(const std::string& arg) {
  std::string lower;
  for (char c : arg) {
    lower += (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c;
  }
  for (const char* prefix :
       {"matrix:", "https://matrix.to/", "http://matrix.to/",
        "https://www.matrix.to/", "http://www.matrix.to/"}) {
    if (lower.rfind(prefix, 0) == 0) return true;
  }
  return false;
}

BOOL CALLBACK FindOxiTalkWindow(HWND window, LPARAM found) {
  if (::GetPropW(window, FlutterWindow::kWindowProperty) == nullptr) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(found) = window;
  return FALSE;
}

// Hands the link among |args| to the OxiTalk that runs and brings its window to the
// front. Waits a few seconds for a window that is still starting.
void HandToRunningInstance(const std::vector<std::string>& args) {
  HWND window = nullptr;
  for (int attempt = 0; attempt < 25 && window == nullptr; ++attempt) {
    ::EnumWindows(FindOxiTalkWindow, reinterpret_cast<LPARAM>(&window));
    if (window == nullptr) ::Sleep(200);
  }
  if (window == nullptr) return;
  for (const std::string& arg : args) {
    if (!IsMatrixLink(arg)) continue;
    COPYDATASTRUCT data{};
    data.dwData = FlutterWindow::kLinkMessage;
    data.cbData = static_cast<DWORD>(arg.size());
    data.lpData = const_cast<char*>(arg.data());
    ::SendMessageTimeoutW(window, WM_COPYDATA, 0,
                          reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                          5000, nullptr);
    break;
  }
  if (::IsIconic(window)) ::ShowWindow(window, SW_RESTORE);
  ::SetForegroundWindow(window);
}

bool SetString(const wchar_t* key, const wchar_t* name,
               const std::wstring& value) {
  return ::RegSetKeyValueW(
             HKEY_CURRENT_USER, key, name, REG_SZ, value.c_str(),
             static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
}

// Registers OxiTalk for matrix: links, for this user (no admin rights), and again when
// the exe moved; a scheme another app has (another Matrix client) is left to it.
void RegisterMatrixScheme() {
  wchar_t exe[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  if (length == 0 || length == MAX_PATH) return;
  const std::wstring path(exe, length);
  const std::wstring command = L"\"" + path + L"\" \"%1\"";

  wchar_t current[2 * MAX_PATH] = L"";
  DWORD size = sizeof(current);
  if (::RegGetValueW(HKEY_CURRENT_USER, kCommandKey, nullptr, RRF_RT_REG_SZ,
                     nullptr, current, &size) == ERROR_SUCCESS) {
    std::wstring existing(current);
    if (existing == command) return;
    for (auto& c : existing) c = static_cast<wchar_t>(std::towlower(c));
    if (existing.find(L"oxitalk") == std::wstring::npos) return;
  }
  SetString(kSchemeKey, nullptr, L"URL:Matrix link");
  SetString(kSchemeKey, L"URL Protocol", L"");
  SetString(L"Software\\Classes\\matrix\\DefaultIcon", nullptr,
            L"\"" + path + L"\",0");
  SetString(kCommandKey, nullptr, command);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Already running: the link goes there (kept open until this process ends).
  ::CreateMutexW(nullptr, FALSE, kInstanceMutex);
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HandToRunningInstance(command_line_arguments);
    return EXIT_SUCCESS;
  }
  RegisterMatrixScheme();

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"oxitalk", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
