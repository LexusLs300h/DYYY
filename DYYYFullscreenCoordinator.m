#import "DYYYFullscreenCoordinator.h"
#import "DYYYFullscreenGeometry.h"
#import "DYYYUtils.h"
#import "DYYYFloatingButtonCoordinator.h"
#import "AwemeHeaders.h"
#import <objc/runtime.h>

@interface DYYYFullscreenPlayerState : NSObject
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, assign) CGSize layoutWindowSize;
@property(nonatomic, assign) UIEdgeInsets layoutSafeArea;
@property(nonatomic, assign) CGRect nativeFrame;
@property(nonatomic, assign) CGRect lastAppliedFrame;
@property(nonatomic, assign) BOOL hasNativeFrame;
@property(nonatomic, assign) CGSize closedInteractionSize;
@property(nonatomic, assign) CGRect captionWindowFrame;
@property(nonatomic, assign) BOOL hasCaptionFrame;
@property(nonatomic, assign) BOOL captionAdjusted;
@property(nonatomic, assign) CGPoint captionNativeCenter;
@property(nonatomic, assign) CGPoint captionAppliedCenter;
@property(nonatomic, assign) BOOL applying;
@property(nonatomic, assign) BOOL adjusted;
@property(nonatomic, assign) CGRect normalWindowFrame;
@property(nonatomic, assign) BOOL hasNormalWindowFrame;
@property(nonatomic, assign) CGSize normalRenderSize;
@property(nonatomic, weak) UIWindow *normalWindow;
@property(nonatomic, weak) UIView *normalCell;
@property(nonatomic, assign) CGRect normalCellWindowFrame;
@property(nonatomic, assign) CGAffineTransform nativeImageTransform;
@property(nonatomic, assign) CGAffineTransform closedImageTransform;
@property(nonatomic, assign) BOOL hasImageTransform;
@property(nonatomic, assign) BOOL hasClosedImageTransform;
@property(nonatomic, assign) BOOL imageAdjusted;
@property(nonatomic, weak) UIImageView *imageContent;
@property(nonatomic, assign) BOOL mediaHost;
@property(nonatomic, assign) CGRect mediaHostParentBounds;
@property(nonatomic, assign) BOOL bottomBarEnabled;
@property(nonatomic, assign) CGRect nativeHostFrame;
@property(nonatomic, assign) CGRect fullscreenHostFrame;
@property(nonatomic, strong) NSMapTable<UIView *, NSDictionary *> *bottomBackgrounds;
@property(nonatomic, weak) UIView *transparentBottomBar;
@property(nonatomic, assign) BOOL applyingBottomBackground;
@property(nonatomic, assign) BOOL updatingBottomBar;
@end
@implementation DYYYFullscreenPlayerState
@end

@implementation DYYYFullscreenCoordinator
+ (NSString *)buildIdentifier { return @"fullscreen-creator-native-20261024.2"; }
+ (NSString *)contentSourceForController:(UIViewController *)controller {
    // 以当前内容来源为准，不能仅凭它仍挂在首页导航栈中判断。
    for (NSUInteger depth = 0; controller && depth < 8; depth++, controller = controller.parentViewController) {
        if (![controller respondsToSelector:@selector(referString)]) continue;
        NSString *refer = [(AWEPlayInteractionViewController *)controller referString];
        if (refer.length > 0) return refer;
    }
    return nil;
}
+ (BOOL)usesRecommendedLayoutForController:(UIViewController *)controller {
    return [[self contentSourceForController:controller] isEqualToString:@"homepage_hot"];
}
+ (BOOL)usesDetailLayoutForController:(UIViewController *)controller {
    Class detailClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    Class remoteClass = NSClassFromString(@"AFDPlayRemoteFeedTableViewController");
    BOOL detail = NO;
    for (NSUInteger depth = 0; controller && depth < 8; depth++, controller = controller.parentViewController) {
        if (remoteClass && [controller isKindOfClass:remoteClass]) return NO;
        if ([controller isKindOfClass:detailClass]) detail = YES;
    }
    return detail;
}
+ (UIScrollView *)pagingViewForCell:(UIView *)cell {
    for (UIView *view = cell.superview; view; view = view.superview) {
        if ([view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]]) return (UIScrollView *)view;
    }
    return nil;
}
+ (BOOL)view:(UIView *)view spansWidthOf:(UIView *)container {
    return view && container && container.bounds.size.width > 0 && fabs(view.bounds.size.width - container.bounds.size.width) <= 1;
}
+ (BOOL)usesFullscreenLayoutForController:(UIViewController *)controller {
    Class remoteClass = NSClassFromString(@"AFDPlayRemoteFeedTableViewController");
    BOOL pureMode = NO;
    for (UIViewController *parent = controller; parent; parent = parent.parentViewController) {
        if (remoteClass && [parent isKindOfClass:remoteClass]) return NO;
        if ([parent respondsToSelector:@selector(getPureModeContainerFrame)]) pureMode = YES;
    }
    if (pureMode || [self usesRecommendedLayoutForController:controller] || [self usesDetailLayoutForController:controller]) return YES;
    UIView *view = controller.viewIfLoaded;
    if (!view.window) return NO;
    UIView *cell = [self cellForPlayer:view owner:controller];
    if (![cell isKindOfClass:[UITableViewCell class]] && ![cell isKindOfClass:[UICollectionViewCell class]]) return NO;
    UIScrollView *pager = [self pagingViewForCell:cell];
    if (![self view:cell spansWidthOf:pager] || pager.bounds.size.height <= 0) return NO;
    // 分页能力和实际容器决定是否适配，窗口大小、设备型号不参与分类。
    if (pager.pagingEnabled) return YES;
    for (UIViewController *parent = controller; parent; parent = parent.parentViewController) {
        if ([parent respondsToSelector:@selector(currentVisibleCellIndex)]) return YES;
    }
    return NO;
}
+ (CGRect)frameForPureModeContainer:(UIViewController *)controller proposed:(CGRect)frame {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYEnableFullScreen")) return frame;
    UIView *view = controller.viewIfLoaded;
    if (!view) return frame;
    if (CGRectIsEmpty(frame) || CGRectIsNull(frame) || CGRectIsInfinite(frame) || fabs(frame.size.width - view.bounds.size.width) > 1) return frame;
    CGFloat height = CGRectGetMaxY(view.bounds) - frame.origin.y;
    // 交给原生列表同步计算行高和分页，媒体可延伸到底部清屏控制栏下方。
    if (height > 0) frame.size.height = height;
    return frame;
}
+ (CGFloat)bottomInsetForDetail:(CGFloat)inset controller:(UIViewController *)controller {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYEnableFullScreen") || ![self usesDetailLayoutForController:controller]) return inset;
    UIView *view = controller.viewIfLoaded;
    if (!view.window || CGRectIsEmpty(view.bounds)) return inset;
    // 行高只以本页原生视口为准；未加载时保留原生值，显示后统一修正缓存。
    return inset > 0 ? 0 : inset;
}
+ (CGFloat)heightForDetailRow:(CGFloat)height table:(UITableView *)table controller:(UIViewController *)controller {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYEnableFullScreen") || ![self usesDetailLayoutForController:controller]) return height;
    // 行高与 UITableView 分页视口使用同一尺寸，预加载时也不扣第二次底栏。
    return height > 0 && table.bounds.size.height > 0 ? table.bounds.size.height : height;
}
+ (void)reconcileDetailPaging:(UIViewController *)controller {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYEnableFullScreen") || ![self usesDetailLayoutForController:controller]) return;
    if (![controller respondsToSelector:@selector(tableView)] || ![controller respondsToSelector:@selector(currentVisibleCellIndex)] ||
        ![controller respondsToSelector:@selector(updateTableViewLayoutForTargetPageIndex:)]) return;
    AWEAwemeDetailTableViewController *detail = (AWEAwemeDetailTableViewController *)controller;
    UITableView *table = [detail tableView];
    CGFloat height = table.bounds.size.height;
    if (!table.window || height <= 0 || table.bounds.size.width <= 0 || [self hasCommentInWindow:table.window] ||
        table.tracking || table.dragging || table.decelerating || table.numberOfSections != 1) return;
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(table, @selector(state:));
    if (state.applying) return;
    NSInteger count = [table numberOfRowsInSection:0];
    NSUInteger index = [detail currentVisibleCellIndex];
    if (count <= 0 || index >= (NSUInteger)count) return;
    NSIndexPath *firstIndex = [NSIndexPath indexPathForRow:0 inSection:0];
    NSIndexPath *lastIndex = [NSIndexPath indexPathForRow:count - 1 inSection:0];
    CGRect first = [table rectForRowAtIndexPath:firstIndex];
    CGRect last = [table rectForRowAtIndexPath:lastIndex];
    if (fabs(first.size.height - height) < 0.5 && fabs(last.size.height - height) < 0.5 &&
        fabs(CGRectGetMinY(last) - CGRectGetMinY(first) - (count - 1) * height) < 0.5) return;
    if (![detail respondsToSelector:@selector(tableView:heightForRowAtIndexPath:)] ||
        fabs([detail tableView:table heightForRowAtIndexPath:firstIndex] - height) > 0.5 ||
        fabs([detail tableView:table heightForRowAtIndexPath:lastIndex] - height) > 0.5) return;
    state = [self state:table];
    state.applying = YES;
    @try {
        // 早期数据源可能已缓存带输入栏占位的行高；只改视口不会清除这些缓存。
        // 批量更新重新询问原生行高，随后按同一个视频索引恢复原生分页偏移。
        [UIView performWithoutAnimation:^{
            [table beginUpdates];
            [table endUpdates];
            [detail updateTableViewLayoutForTargetPageIndex:(NSInteger)index];
            [table layoutIfNeeded];
        }];
    } @finally {
        state.applying = NO;
    }
}
+ (void)layoutBottomBar:(UIView *)bar controller:(UIViewController *)controller enabled:(BOOL)enabled {
    DYYYFullscreenPlayerState *state = [self state:bar];
    if (state.updatingBottomBar) return;
    state.updatingBottomBar = YES;
    @try {
        enabled = enabled && !CGRectIsEmpty(bar.bounds);
        state.owner = controller;
        state.bottomBarEnabled = enabled;
        if (!enabled) {
            for (UIView *view in state.bottomBackgrounds.keyEnumerator.allObjects) {
                NSDictionary *saved = [state.bottomBackgrounds objectForKey:view];
                DYYYFullscreenPlayerState *target = [self state:view];
                target.applyingBottomBackground = YES;
                view.backgroundColor = saved[@"color"] == [NSNull null] ? nil : saved[@"color"];
                view.opaque = [saved[@"opaque"] boolValue];
                if (view != bar && saved[@"hidden"] && view.hidden != [saved[@"hidden"] boolValue]) view.hidden = [saved[@"hidden"] boolValue];
                if ([view isKindOfClass:[UIVisualEffectView class]]) ((UIVisualEffectView *)view).effect = saved[@"effect"] == [NSNull null] ? nil : saved[@"effect"];
                target.transparentBottomBar = nil;
                target.applyingBottomBackground = NO;
            }
            state.bottomBackgrounds = nil;
            return;
        }
        if (!state.bottomBackgrounds) state.bottomBackgrounds = [NSMapTable weakToStrongObjectsMapTable];
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:bar];
        for (NSUInteger i = 0; i < queue.count && i < 32; i++) {
            UIView *view = queue[i];
            CGRect rect = [view convertRect:view.bounds toView:bar];
            BOOL coversBar = rect.size.width >= bar.bounds.size.width - 1 && rect.size.height >= bar.bounds.size.height - 1;
            BOOL decoration = ![view isKindOfClass:[UIControl class]] && ![view isKindOfClass:[UILabel class]];
            
            // 41.1.0 修复：放宽底部背景的判断，兼容原生底栏的结构变化
            BOOL background = view == bar || 
                [view isKindOfClass:[UIVisualEffectView class]] ||
                [view isKindOfClass:[UIImageView class]] || 
                [NSStringFromClass(view.class) containsString:@"Background"] || 
                [NSStringFromClass(view.class) containsString:@"Blur"] || 
                (decoration && coversBar);
                
            if (background) {
                UIView *skin = [bar respondsToSelector:@selector(skinContainerView)] ? [(AWENormalModeTabBar *)bar skinContainerView] : nil;
                BOOL backgroundOnly = view != bar && (view == skin || [NSStringFromClass(view.class) containsString:@"Background"] || [view isKindOfClass:[UIImageView class]]);
                if (![state.bottomBackgrounds objectForKey:view]) {
                    UIVisualEffect *effect = [view isKindOfClass:[UIVisualEffectView class]] ? ((UIVisualEffectView *)view).effect : nil;
                    NSMutableDictionary *saved = [@{@"color": view.backgroundColor ?: [NSNull null], @"opaque": @(view.opaque), @"effect": effect ?: [NSNull null]} mutableCopy];
                    if (coversBar && backgroundOnly) saved[@"hidden"] = @(view.hidden);
                    [state.bottomBackgrounds setObject:saved forKey:view];
                }
                DYYYFullscreenPlayerState *target = [self state:view];
                target.transparentBottomBar = bar;
                target.applyingBottomBackground = YES;
                if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > 0) view.backgroundColor = UIColor.clearColor;
                if (view.opaque) view.opaque = NO;
                if (coversBar && backgroundOnly && !view.hidden) view.hidden = YES;
                if ([view isKindOfClass:[UIVisualEffectView class]] && ((UIVisualEffectView *)view).effect) ((UIVisualEffectView *)view).effect = nil;
                target.applyingBottomBackground = NO;
            }
            if (queue.count < 32 && ![view isKindOfClass:[UIControl class]]) [queue addObjectsFromArray:view.subviews];
        }
    } @finally {
        state.updatingBottomBar = NO;
    }

}
+ (UIColor *)backgroundForBottomView:(UIView *)view proposed:(UIColor *)color {
    DYYYFullscreenPlayerState *target = objc_getAssociatedObject(view, @selector(state:));
    UIView *bar = target.transparentBottomBar;
    if (!bar || target.applyingBottomBackground) return color;
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(bar, @selector(state:));
    NSDictionary *saved = [state.bottomBackgrounds objectForKey:view];
    if (!saved) return color;
    NSMutableDictionary *updated = [saved mutableCopy];
    updated[@"color"] = color ?: [NSNull null];
    [state.bottomBackgrounds setObject:updated forKey:view];
    return state.bottomBarEnabled && bar.window ? UIColor.clearColor : color;
}
+ (void)layoutBottomInput:(UIView *)view controller:(UIViewController *)controller {
    if (![NSThread isMainThread]) return;
    [self layoutBottomBar:view controller:controller enabled:DYYYGetBool(@"DYYYEnableFullScreen") && [self usesDetailLayoutForController:controller]];
}
+ (CGFloat)bottomOccupiedHeightForView:(UIView *)view {
    UIWindow *window = view.window;
    if (!window) return 0;
    UIViewController *controller = [DYYYUtils firstAvailableViewControllerFromView:view];
    for (UIViewController *owner = controller; owner; owner = owner.parentViewController) {
        if (![owner respondsToSelector:@selector(activeBottomBar)]) continue;
        UIView *bar = [(AWEAwemeDetailTableViewController *)owner activeBottomBar];
        if (bar.window == window && bar.bounds.size.height > 0) return bar.bounds.size.height;
    }
    // 评论会隐藏底栏，尺寸仍以同一窗口中的真实栏为准。
    for (UIView *bar in [self tabBars].allObjects) if (bar.window == window && bar.bounds.size.height > 0) return bar.bounds.size.height;
    return 0;
}
+ (CGRect)rect:(CGRect)rect followingView:(UIView *)view controller:(UIViewController *)controller anchor:(UIView *)anchor {
    UIWindow *window = view.window;
    UIView *cell = [self cellForPlayer:view owner:controller];
    UIScrollView *pager = [self pagingViewForCell:cell];
    if (window && pager.window == window && [self view:cell spansWidthOf:pager] && ![anchor isDescendantOfView:cell]) {
        // 固定底栏先跟随各自的分页 cell，再换算到文案容器；预加载、复用和
        // 翻页都使用同一个视口基准，不能让屏幕坐标改变每页的文案区域高度。
        CGRect cellRect = [cell convertRect:cell.bounds toView:window];
        CGRect viewport = [pager convertRect:pager.bounds toView:window];
        rect.origin.y += CGRectGetMinY(cellRect) - CGRectGetMinY(viewport);
    }
    return rect;
}
+ (CGRect)bottomBarRect:(UIView *)bar followingView:(UIView *)view controller:(UIViewController *)controller {
    if (!view.window || bar.window != view.window) return CGRectNull;
    return [self rect:[bar convertRect:bar.bounds toView:view.window] followingView:view controller:controller anchor:bar];
}
+ (BOOL)layoutNativeInteraction:(UIViewController *)controller {
    if (![NSThread isMainThread]) return NO;
    UIView *view = controller.viewIfLoaded;
    UIView *parent = view.superview;
    if (view.window) [[self interactions] addObject:controller];
    if (!view.window || ![self view:view spansWidthOf:parent]) return NO;
    BOOL enabled = DYYYGetBool(@"DYYYEnableFullScreen");
    BOOL legacy = [[self contentSourceForController:controller] isEqualToString:@"co_play_watch"];
    for (UIViewController *owner = controller; owner; owner = owner.parentViewController) {
        if (![owner respondsToSelector:@selector(activeBottomBar)]) continue;
        UIView *bar = [(AWEAwemeDetailTableViewController *)owner activeBottomBar];
        if (![bar isKindOfClass:[UIView class]]) continue;
        if (!enabled) { [self layoutBottomBar:bar controller:controller enabled:NO]; continue; }
        if (bar.window != view.window || ![self visible:bar]) continue;
        CGRect barRect = [bar convertRect:bar.bounds toView:view.window];
        UIView *root = owner.viewIfLoaded;
        CGRect rootRect = [root convertRect:root.bounds toView:view.window];
        if (!root || barRect.size.height <= 0 || barRect.size.height >= rootRect.size.height ||
            fabs(barRect.size.width - rootRect.size.width) > 1 || fabs(CGRectGetMaxY(barRect) - CGRectGetMaxY(rootRect)) > 1) continue;
        [self layoutBottomBar:bar controller:controller enabled:YES];
        if (legacy) return NO;
        CGRect frame = view.frame;
        barRect = [self bottomBarRect:bar followingView:view controller:controller];
        CGFloat bottom = CGRectGetMinY([parent convertRect:barRect fromView:view.window]);
        CGFloat height = MIN(CGRectGetMaxY(parent.bounds), bottom) - frame.origin.y;
        if (height <= 0) return NO;
        if (fabs(frame.size.height - height) > 0.25) { frame.size.height = height; view.frame = frame; }
        return YES;
    }
    // 没有普通底栏时，保留原有 referString 规则；合集、一起看等例外继续有效。
    return NO;
}
// Live 图文也含 TTPlayerView 和有效视频尺寸，不能用播放器存在与否区分。
+ (BOOL)isImageContentController:(UIViewController *)controller {
    for (NSUInteger depth = 0; controller && depth < 5; depth++, controller = controller.parentViewController) {
        if (![controller respondsToSelector:@selector(model)]) continue;
        AWEAwemeModel *model = [(AWEPlayInteractionViewController *)controller model];
        if (![model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) continue;
        if ([model respondsToSelector:@selector(awemeType)] && model.awemeType == 68) return YES;
        if ([model respondsToSelector:@selector(albumImages)] && model.albumImages.count > 0) return YES;
        if ([model respondsToSelector:@selector(isLivePhoto)] && model.isLivePhoto) return YES;
        if ([model respondsToSelector:@selector(animatedImageVideoInfo)] && model.animatedImageVideoInfo) return YES;
        return NO;
    }
    return NO;
}
+ (NSHashTable<UIView *> *)players {
    static NSHashTable *players;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ players = [NSHashTable weakObjectsHashTable]; });
    return players;
}
+ (NSHashTable<UIView *> *)images {
    static NSHashTable *images;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ images = [NSHashTable weakObjectsHashTable]; });
    return images;
}
+ (NSHashTable<UIView *> *)tabBars {
    static NSHashTable *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSHashTable weakObjectsHashTable]; });
    return views;
}
+ (NSHashTable<UIViewController *> *)interactions {
    static NSHashTable *controllers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controllers = [NSHashTable weakObjectsHashTable]; });
    return controllers;
}
+ (void)invalidateGuides {
    static BOOL scheduled = NO;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        for (UIViewController *controller in [self interactions].allObjects) [controller.viewIfLoaded setNeedsLayout];
        for (UIView *player in [self players].allObjects) if (player.window) [player setNeedsLayout];
        for (UIView *image in [self images].allObjects) if (image.window) [image setNeedsLayout];
    });
}
+ (void)layoutRootTabBar:(UIView *)bar {
    BOOL playback = NO;
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(bar, @selector(state:));
    if ([self hasCommentInWindow:bar.window] && state.bottomBarEnabled) playback = YES;
    if (!playback) for (UIViewController *controller in [self interactions].allObjects) {
        if (controller.viewIfLoaded.window != bar.window || ![self usesFullscreenLayoutForController:controller] ||
            ![DYYYFloatingButtonCoordinator isControllerVisible:controller]) continue;
        playback = YES;
        break;
    }
    BOOL enabled = DYYYGetBool(@"DYYYHideBottomBg") || (DYYYGetBool(@"DYYYEnableFullScreen") && playback);
    [self layoutBottomBar:bar controller:nil enabled:enabled];
}
+ (void)registerTabBar:(UIView *)tabBar {
    if (![NSThread isMainThread]) return;
    [[self tabBars] addObject:tabBar];
    [self layoutRootTabBar:tabBar];
    CGRect rect = tabBar.window ? [tabBar convertRect:tabBar.bounds toView:tabBar.window] : CGRectNull;
    NSString *signature = [NSString stringWithFormat:@"%p/%@/%d", tabBar.window, NSStringFromCGRect(rect), [self visible:tabBar]];
    NSString *previous = objc_getAssociatedObject(tabBar, @selector(registerTabBar:));
    if (![signature isEqualToString:previous]) {
        objc_setAssociatedObject(tabBar, @selector(registerTabBar:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [self invalidateGuides];
    }
}
+ (void)layoutInteraction:(UIViewController *)controller {
    if (![NSThread isMainThread] || ![self usesRecommendedLayoutForController:controller]) return;
    UIView *view = controller.viewIfLoaded;
    UIView *parent = view.superview;
    if (!view.window || ![self view:view spansWidthOf:parent]) return;
    [[self interactions] addObject:controller];
    for (UIView *bar in [self tabBars].allObjects) if (bar.window == view.window) [self layoutRootTabBar:bar];
    if ([self isImageContentController:controller]) return;
    DYYYFullscreenPlayerState *state = [self state:view];
    state.owner = controller;
    CGRect current = view.frame;
    if (!state.hasNativeFrame || !CGRectEqualToRect(current, state.lastAppliedFrame)) state.nativeFrame = current;
    state.hasNativeFrame = YES;
    CGRect target = state.nativeFrame;
    target.size.height = MIN(target.size.height, MAX(0, CGRectGetMaxY(parent.bounds) - target.origin.y));
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        target.size.height = MAX(0, CGRectGetMaxY(parent.bounds) - target.origin.y);
        CGRect guide = [parent convertRect:target toView:view.window];
        for (UIView *tabBar in [self tabBars].allObjects) {
            // 清屏只隐藏底栏，不释放其占位；信息区沿用同一边界，退出时无需
            // 等待底栏的显隐动画恢复，也不会把文案按全屏高度重新锚到底部。
            if (tabBar.window != view.window || CGRectIsEmpty(tabBar.bounds)) continue;
            CGRect tabRect = [self bottomBarRect:tabBar followingView:view controller:controller];
            if (CGRectIsNull(tabRect)) continue;
            if (CGRectGetMinY(tabRect) < CGRectGetMidY(guide)) continue;
            CGRect available = [DYYYFullscreenGeometry unoccludedViewport:guide top:CGRectGetMinY(guide) panel:tabRect gap:0];
            if (!CGRectIsNull(available)) guide = available;
        }
        target = [parent convertRect:guide fromView:view.window];
    }
    BOOL activeComment = [self hasCommentInWindow:view.window];
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        if (activeComment && state.normalWindow == view.window && state.closedInteractionSize.height > 0) {
            // 评论隐藏 Tab 并不代表信息区可扩高，否则原生底部约束会下跳一个 Tab 高度。
            target.size.height = state.closedInteractionSize.height;
        } else if (!activeComment) {
            state.closedInteractionSize = target.size;
            state.normalWindow = view.window;
        }
    } else {
        state.closedInteractionSize = CGSizeZero;
    }
    state.lastAppliedFrame = target;
    if (fabs(current.size.height - target.size.height) > 0.25 || fabs(current.origin.y - target.origin.y) > 0.25) {
        view.frame = target;
    }
    NSString *signature = [NSString stringWithFormat:@"%@/%d/%d", NSStringFromCGRect(target),
                           DYYYGetBool(@"DYYYEnableFullScreen"), DYYYGetBool(@"DYYYEnableCommentBlur")];
    NSString *previous = objc_getAssociatedObject(controller, @selector(layoutInteraction:));
    if (![signature isEqualToString:previous]) {
        objc_setAssociatedObject(controller, @selector(layoutInteraction:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
        // 仅几何输入变化时更新播放器，不能每次 layout 都再次标记自身。
        for (UIView *player in [self players].allObjects) if (player.window == view.window) [player setNeedsLayout];
    }
}
+ (NSHashTable<UIView *> *)informationLabels {
    static NSHashTable *labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ labels = [NSHashTable weakObjectsHashTable]; });
    return labels;
}
+ (void)layoutInformationLabel:(UIView *)label {
    if (![NSThread isMainThread] || !label.window || !label.superview) return;
    UIViewController *owner = [DYYYUtils firstAvailableViewControllerFromView:label];
    if (![self usesRecommendedLayoutForController:owner]) return;
    DYYYFullscreenPlayerState *state = [self state:label];
    [[self informationLabels] addObject:label];
    BOOL active = DYYYGetBool(@"DYYYEnableFullScreen") && [self hasCommentInWindow:label.window];
    if (!active) {
        if (state.captionAdjusted && CGPointEqualToPoint(label.center, state.captionAppliedCenter)) label.center = state.captionNativeCenter;
        state.captionAdjusted = NO;
        state.captionWindowFrame = [label convertRect:label.bounds toView:label.window];
        state.hasCaptionFrame = DYYYGetBool(@"DYYYEnableFullScreen");
        state.normalWindow = label.window;
        return;
    }
    if (!state.hasCaptionFrame || state.normalWindow != label.window) return;
    CGRect current = [label convertRect:label.bounds toView:label.window];
    CGFloat shift = CGRectGetMaxY(current) - CGRectGetMaxY(state.captionWindowFrame);
    if (shift > 0.25) {
        if (!state.captionAdjusted || !CGPointEqualToPoint(label.center, state.captionAppliedCenter)) state.captionNativeCenter = label.center;
        // 只拦截越过关闭态底边的下移，保留普通评论合法的向上平移和缩放。
        CGRect target = current;
        target.origin.y -= shift;
        CGPoint center = label.center;
        center.y += CGRectGetMidY([label.superview convertRect:target fromView:label.window]) - CGRectGetMidY(label.frame);
        state.captionAppliedCenter = center;
        state.captionAdjusted = YES;
        label.center = center;
    }
}
+ (void)rememberInteractionGuide:(UIViewController *)controller {
    UIView *view = controller.viewIfLoaded;
    if (![NSThread isMainThread] || ![self usesRecommendedLayoutForController:controller] || !view.window || !DYYYGetBool(@"DYYYEnableFullScreen") || [self hasCommentInWindow:view.window]) return;
    DYYYFullscreenPlayerState *state = [self state:view];
    state.owner = controller;
    state.closedInteractionSize = view.frame.size;
    state.normalWindow = view.window;
}
+ (BOOL)keepsMediaHostFullscreen:(UIView *)view state:(DYYYFullscreenPlayerState *)state {
    return state.mediaHost && !state.applying && state.normalWindow == view.window &&
        CGRectEqualToRect(state.mediaHostParentBounds, view.superview.bounds) &&
        DYYYGetBool(@"DYYYEnableFullScreen") && [self usesFullscreenLayoutForController:state.owner];
}
+ (CGRect)boundsForMediaHost:(UIView *)view proposed:(CGRect)bounds {
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(view, @selector(state:));
    if (![self keepsMediaHostFullscreen:view state:state]) return bounds;
    CGRect native = state.nativeHostFrame;
    CGPoint center = CGPointMake(CGRectGetMidX(native), CGRectGetMidY(native));
    native.size = bounds.size;
    native.origin = CGPointMake(center.x - bounds.size.width * 0.5, center.y - bounds.size.height * 0.5);
    state.nativeHostFrame = native;
    return (CGRect){CGPointZero, state.fullscreenHostFrame.size};
}
+ (CGPoint)centerForMediaHost:(UIView *)view proposed:(CGPoint)center {
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(view, @selector(state:));
    if (![self keepsMediaHostFullscreen:view state:state]) return center;
    CGRect native = state.nativeHostFrame;
    native.origin = CGPointMake(center.x - native.size.width * 0.5, center.y - native.size.height * 0.5);
    state.nativeHostFrame = native;
    return CGPointMake(CGRectGetMidX(state.fullscreenHostFrame), CGRectGetMidY(state.fullscreenHostFrame));
}
+ (CGRect)frameForInteractionView:(UIView *)view proposed:(CGRect)frame {
    // 只访问已注册的互动根视图和媒体承载区，不遍历普通视图的 responder。
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(view, @selector(state:));
    if ([self keepsMediaHostFullscreen:view state:state]) {
        state.nativeHostFrame = frame;
        return state.fullscreenHostFrame;
    }
    if (state.closedInteractionSize.height > 0 && [self usesRecommendedLayoutForController:state.owner] && state.normalWindow == view.window &&
        fabs(frame.size.width - state.closedInteractionSize.width) <= 1 &&
        DYYYGetBool(@"DYYYEnableFullScreen") && [self hasCommentInWindow:view.window]) {
        frame.size.height = state.closedInteractionSize.height;
    }
    return frame;
}
+ (NSHashTable<UIViewController *> *)comments {
    static NSHashTable *comments;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ comments = [NSHashTable weakObjectsHashTable]; });
    return comments;
}
+ (NSMapTable<UIWindow *, NSNumber *> *)pendingComments {
    static NSMapTable *windows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ windows = [NSMapTable weakToStrongObjectsMapTable]; });
    return windows;
}
+ (NSMapTable<UIViewController *, UIWindow *> *)commentWindows {
    static NSMapTable *windows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ windows = [NSMapTable weakToWeakObjectsMapTable]; });
    return windows;
}
+ (void)beginCommentInWindow:(UIWindow *)window {
    if (![NSThread isMainThread] || !window || !DYYYGetBool(@"DYYYEnableFullScreen")) return;
    if (![self hasCommentInWindow:window]) {
        for (UIView *label in [self informationLabels].allObjects) {
            if (label.window != window || ![self visible:label]) continue;
            [self layoutInformationLabel:label];
        }
    }
    // 先冻结关闭态，再执行原生打开动作。动画开始早于 viewDidLayoutSubviews。
    // 未成功显示的面板自动在 5 秒后失效，不留下持续的 UI 工作。
    [[self pendingComments]
