//
//  jsb_cocosruntime.mm
//  CocosJSRuntime
//
//  Created by WenhaiLin on 15/10/23.
//
#include "jsb_cocosruntime.h"
#include "cocos2d_specifics.hpp"
#include "network/NetworkHelper.h"
#include "sdk/LoadingDelegate.h"
#import "sdk/CocosRuntimeGroup.h"

std::function<void (int percent, bool isFailed)> s_downloadCallback;

@interface PreloadCallbackWapper : NSObject<LoadingDelegate>

@end

@implementation PreloadCallbackWapper

- (void) onLoadingProgress:(NSInteger)progress :(bool) isFailed;
{
    if (s_downloadCallback) {
        s_downloadCallback((int)progress, isFailed);
    }
}

- (void) onPreRunGameCompleted
{
    if (s_downloadCallback) {
        s_downloadCallback(100, false);
    }
}

@end

static PreloadCallbackWapper* s_preloadWapper = nil;

USING_NS_CC;

static bool JSB_runtime_preload(JSContext *cx, uint32_t argc, jsval *vp)
{
    JSB_PRECONDITION2( argc == 3, cx, false, "JSB_runtime_preload Invalid number of arguments" );
    
    auto args = JS::CallArgsFromVp(argc, vp);
    bool ok = true;

    std::string arg0 = "";
    auto arg0Handle = args.get(0);

    if (JS_IsArrayObject(cx, arg0Handle))
    {
        // It's a group array
        ValueVector arrVal;
        ok = jsval_to_ccvaluevector(cx, arg0Handle, &arrVal);

        for (size_t i = 0; i < arrVal.size(); i++) {
            if (! arg0.empty()) {
                arg0 += ":";
            }

            arg0 += arrVal[i].asString();
        }
    }
    else
    {
        // only one group
        ok &= jsval_to_std_string(cx, args.get(0), &arg0);
    }

    JSB_PRECONDITION2(ok, cx, false, "Error processing arguments");

    do {
        if (JS_TypeOfValue(cx, args[1]) == JSTYPE_FUNCTION) {
            JSObject* cbObject;
            if (args.get(2).isObject()) {
                cbObject = args.get(2).toObjectOrNull();
            } else {
                
            }
            
            std::shared_ptr<JSFunctionWrapper> func (new JSFunctionWrapper(cx, cbObject, args[1]));
            auto lambda = [=](int percent, bool isFailed) -> void {
                Director::getInstance()->getScheduler()->performFunctionInCocosThread([=]{
                    jsval largv[1];
                    do {
                        char statusText[60];
                        sprintf(statusText, "{percent:%d, isCompleted:%s, isFailed:%s}", percent,
                                (percent >= 100 && !isFailed) ? "true" : "false",
                                isFailed ? "true" : "false");
                            
                        largv[0] = c_string_to_jsval(cx, statusText);
                    } while (false);
                    
                    JS::RootedValue rval(cx);
                    auto invoke_ok = func->invoke(1, &largv[0], &rval);
                    if (!invoke_ok && JS_IsExceptionPending(cx)) {
                        JS_ReportPendingException(cx);
                    }
                });
                
            };
            s_downloadCallback = lambda;
        }
        else {
            s_downloadCallback = nullptr;
        }
    } while (false);
    
    if (s_downloadCallback) {
        NSString* groups = [NSString stringWithUTF8String:arg0.c_str()];
        if (s_preloadWapper == nil) {
            s_preloadWapper = [[PreloadCallbackWapper alloc] init];
        }
        [CocosRuntimeGroup preloadResGroups:groups delegate:s_preloadWapper];
    }
    
    args.rval().setUndefined();
    
    return true;
}

static bool JSB_runtime_getNetworkType(JSContext *cx, uint32_t argc, jsval *vp) {
    JSB_PRECONDITION2( argc == 0, cx, false, "JSB_runtime_getNetworkType Invalid number of arguments" );
    
    auto args = JS::CallArgsFromVp(argc, vp);
    int status = [NetworkHelper getNetworkType];
    args.rval().set(INT_TO_JSVAL(status));
    
    return true;
}

void jsb_register_cocosruntime(JSContext* cx, JS::HandleObject global)
{
    JS::RootedObject runtimeObj(cx);
    get_or_create_js_obj(cx, global, "runtime", &runtimeObj);

    JS_DefineFunction(cx, runtimeObj, "preload", JSB_runtime_preload, 3, JSPROP_READONLY | JSPROP_PERMANENT | JSPROP_ENUMERATE );
    
    JS_DefineFunction(cx, runtimeObj, "getNetworkType", JSB_runtime_getNetworkType, 0, JSPROP_READONLY | JSPROP_PERMANENT | JSPROP_ENUMERATE );
}
