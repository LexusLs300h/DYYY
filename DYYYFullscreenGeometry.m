#import "DYYYFullscreenGeometry.h"
#import <math.h>

static BOOL DYYYFullscreenRectIsFinite(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
           isfinite(rect.size.width) && isfinite(rect.size.height);
}

@implementation DYYYFullscreenGeometry
+ (CGRect)translateRect:(CGRect)rect fromReference:(CGRect)previous toReference:(CGRect)current {
    if (!DYYYFullscreenRectIsFinite(rect) || CGRectIsNull(rect) || CGRectIsEmpty(rect) ||
        !DYYYFullscreenRectIsFinite(previous) || CGRectIsNull(previous) || CGRectIsEmpty(previous) ||
        !DYYYFullscreenRectIsFinite(current) || CGRectIsNull(current) || CGRectIsEmpty(current) ||
        fabs(previous.size.width - current.size.width) > 0.5 ||
        fabs(previous.size.height - current.size.height) > 0.5) return CGRectNull;

    // 基准来自稳定的 Feed cell，只抵消翻页位移，不继承评论内部宿主的缩放。
    CGRect translated = CGRectOffset(rect, current.origin.x - previous.origin.x,
                                     current.origin.y - previous.origin.y);
    return DYYYFullscreenRectIsFinite(translated) && !CGRectIsNull(translated) && !CGRectIsEmpty(translated)
        ? translated : CGRectNull;
}
+ (CGRect)aspectFit:(CGSize)media inRect:(CGRect)viewport {
    if (!isfinite(media.width) || !isfinite(media.height) || media.width <= 0 || media.height <= 0 ||
        !DYYYFullscreenRectIsFinite(viewport) || CGRectIsEmpty(viewport) ||
        CGRectIsNull(viewport) || CGRectIsInfinite(viewport)) return CGRectNull;
    CGFloat scale = MIN(viewport.size.width / media.width, viewport.size.height / media.height);
    if (!isfinite(scale) || scale <= 0) return CGRectNull;
    CGSize size = CGSizeMake(media.width * scale, media.height * scale);
    CGRect fit = CGRectMake(CGRectGetMidX(viewport) - size.width / 2,
                            CGRectGetMidY(viewport) - size.height / 2,
                            size.width, size.height);
    return DYYYFullscreenRectIsFinite(fit) && !CGRectIsEmpty(fit) ? fit : CGRectNull;
}
+ (CGAffineTransform)aspectFitTransformForBounds:(CGRect)bounds contentRect:(CGRect)content center:(CGPoint)center inRect:(CGRect)viewport {
    if (!DYYYFullscreenRectIsFinite(bounds) || CGRectIsNull(bounds) || CGRectIsEmpty(bounds) ||
        !DYYYFullscreenRectIsFinite(content) || CGRectIsNull(content) || CGRectIsEmpty(content) ||
        !isfinite(center.x) || !isfinite(center.y)) return CGAffineTransformIdentity;
    CGRect fit = [self aspectFit:content.size inRect:viewport];
    if (CGRectIsNull(fit)) return CGAffineTransformIdentity;
    CGFloat scale = fit.size.width / content.size.width;
    CGFloat tx = CGRectGetMidX(fit) - center.x - (CGRectGetMidX(content) - CGRectGetMidX(bounds)) * scale;
    CGFloat ty = CGRectGetMidY(fit) - center.y - (CGRectGetMidY(content) - CGRectGetMidY(bounds)) * scale;
    if (!isfinite(scale) || !isfinite(tx) || !isfinite(ty) || scale <= 0) return CGAffineTransformIdentity;
    return CGAffineTransformMake(scale, 0, 0, scale, tx, ty);
}
+ (CGRect)unoccludedViewport:(CGRect)viewport top:(CGFloat)top panel:(CGRect)panel gap:(CGFloat)gap {
    if (!DYYYFullscreenRectIsFinite(viewport) || CGRectIsNull(viewport) ||
        CGRectIsInfinite(viewport) || CGRectIsEmpty(viewport) ||
        !isfinite(top) || !isfinite(gap) || gap < 0) return CGRectNull;
    if (!CGRectIsNull(panel) && (!DYYYFullscreenRectIsFinite(panel) || CGRectIsInfinite(panel) || CGRectIsEmpty(panel))) return CGRectNull;
    CGFloat bottom = CGRectGetMaxY(viewport);
    top = MAX(top, CGRectGetMinY(viewport));
    if (!CGRectIsNull(panel) && CGRectIntersectsRect(viewport, panel)) bottom = MIN(bottom, CGRectGetMinY(panel) - gap);
    if (!isfinite(bottom) || bottom <= top) return CGRectNull;
    CGRect available = CGRectMake(viewport.origin.x, top, viewport.size.width, bottom - top);
    return DYYYFullscreenRectIsFinite(available) && !CGRectIsEmpty(available) ? available : CGRectNull;
}

@end
