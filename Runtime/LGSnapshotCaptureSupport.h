#pragma once

#import <UIKit/UIKit.h>

UIImage *LGCaptureViewHierarchySnapshot(UIView *view, CGRect drawRect, CGSize canvasSize, CGFloat scale, BOOL afterUpdates);
BOOL LGDrawViewHierarchyIntoCurrentContext(UIView *view, CGRect drawRect, BOOL afterUpdates);
