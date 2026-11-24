ARCH := $(shell uname -m)
SDK := $(shell xcrun --show-sdk-path)
TARGET := $(ARCH)-apple-macosx13.0
APP := build/macsvn.app
APPEX := $(APP)/Contents/PlugIns/FinderSync.appex
SWIFTC := xcrun swiftc -sdk $(SDK) -target $(TARGET) -g -Onone

APP_SRC := $(wildcard Sources/App/*.swift) $(wildcard Sources/SvnCore/*.swift)
EXT_SRC := Sources/FinderSync/FinderSync.swift $(wildcard Sources/SvnCore/*.swift)

# 默认 ad-hoc。有 Apple 开发证书时：
#   make MACSVN_SIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)"
# 或直接 export MACSVN_SIGN_IDENTITY，install.sh 会读取同一个变量。
IDENTITY ?= -

.PHONY: all clean test verify

all: $(APP)/Contents/MacOS/macsvn

$(APP)/Contents/MacOS/macsvn: $(APP_SRC) $(EXT_SRC) Config/App-Info.plist Config/Finder-Info.plist
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources $(APPEX)/Contents/MacOS $(APPEX)/Contents/Resources
	$(SWIFTC) -framework AppKit -framework CoreServices -framework Security -o $(APP)/Contents/MacOS/macsvn $(APP_SRC)
	# 扩展必须链接成 MH_EXECUTE 并把入口点设成 NSExtensionMain。
	# 用 -bundle 生成的是 MH_BUNDLE，codesign 不会把 entitlements 写进这类文件，
	# 于是 app-sandbox 丢失，pkd 会以 "plug-ins must be sandboxed" 拒绝登记。
	$(SWIFTC) -parse-as-library \
		-Xlinker -e -Xlinker _NSExtensionMain \
		-module-name MacsvnFinder \
		-framework AppKit -framework FinderSync -framework CoreServices -framework Foundation \
		-o $(APPEX)/Contents/MacOS/FinderSync $(EXT_SRC)
	cp Config/App-Info.plist $(APP)/Contents/Info.plist
	cp Config/Finder-Info.plist $(APPEX)/Contents/Info.plist
	cp Config/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Config/AppIcon.icns $(APPEX)/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(IDENTITY)" --entitlements Config/FinderSync.entitlements $(APPEX)
	codesign --force --sign "$(IDENTITY)" --entitlements Config/App.entitlements $(APP)
	$(MAKE) verify

# 构建自检：确认沙盒 entitlement 真的进了扩展，否则装上去也不会被登记。
verify:
	@printf '=== 扩展类型 ===\n'; file $(APPEX)/Contents/MacOS/FinderSync
	@printf '=== 扩展 entitlements ===\n'
	@codesign -d --entitlements :- $(APPEX) 2>/dev/null | grep -q 'com.apple.security.app-sandbox' \
		&& echo 'app-sandbox: 已写入' \
		|| (echo '错误：扩展缺少 app-sandbox entitlement，pkd 会拒绝登记。' && exit 1)

test:
	swift run --build-system native CoreChecks

clean:
	rm -rf build .build
