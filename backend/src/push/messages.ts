/**
 * The words of a push alert. Events of one kind that arrived in the same
 * minute go out as one alert, so ten 공감 make one buzz, not ten.
 */
export type PushKind = 'empathy' | 'follow' | 'post';

/** New events of one kind for one person since the last run. */
export interface PushBatch {
  userId: string;
  lang: string;
  kind: PushKind;
  count: number;
  /** The most recent event's actor, post and words. */
  actorId: string;
  actorName: string;
  postId: string | null;
  excerpt: string | null;
  /** The events are about more than one post, so a tap opens the list. */
  manyPosts?: boolean;
}

export interface PushMessage {
  title: string;
  body: string;
  /** Where a tap opens: a post, a person, or the notifications tab. */
  data: { kind: PushKind; postId?: string; userId?: string };
  /** Unread notifications, shown on the app icon. */
  badge?: number;
}

const short = (text: string | null, max = 60) => {
  const t = (text ?? '').replace(/\s+/g, ' ').trim();
  return [...t].length > max ? `${[...t].slice(0, max - 1).join('')}…` : t;
};

export function compose(b: PushBatch, badge?: number): PushMessage {
  const m = words(b);
  return badge === undefined ? m : { ...m, badge };
}

function words(b: PushBatch): PushMessage {
  const ko = b.lang !== 'en';
  const others = b.count - 1;
  const name = short(b.actorName, 20);
  const excerpt = short(b.excerpt);
  switch (b.kind) {
    case 'empathy':
      return {
        title: ko
          ? others > 0 ? `${name}님 외 ${others}명이 공감했어요` : `${name}님이 공감했어요`
          : others > 0 ? `${name} and ${others} ${others === 1 ? 'other' : 'others'} related` : `${name} related`,
        body: b.manyPosts ? (ko ? '여러 생각에 공감이 모였어요.' : 'Across several of your thoughts.') : excerpt,
        data: { kind: 'empathy', ...(b.postId && !b.manyPosts ? { postId: b.postId } : {}) },
      };
    case 'follow':
      return {
        title: ko
          ? others > 0 ? `${name}님 외 ${others}명이 팔로우했어요` : `${name}님이 팔로우했어요`
          : others > 0 ? `${name} and ${others} ${others === 1 ? 'other' : 'others'} followed you` : `${name} followed you`,
        body: ko ? '누가 내 생각을 읽고 있는지 보세요.' : 'See who is reading your thoughts.',
        data: others > 0 ? { kind: 'follow' } : { kind: 'follow', userId: b.actorId },
      };
    case 'post':
      return {
        title: ko
          ? others > 0 ? `새 생각 ${b.count}개` : `${name}님의 새 생각`
          : others > 0 ? `${b.count} new thoughts` : `A new thought from ${name}`,
        body: others > 0 ? (ko ? `${name}님 외 ${others}명이 새로 썼어요.` : `${name} and others wrote.`) : excerpt,
        data: others > 0 || !b.postId ? { kind: 'post' } : { kind: 'post', postId: b.postId },
      };
  }
}
