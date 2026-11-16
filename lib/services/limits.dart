/// 무료 버전에서 사람 탭에 등록할 수 있는 사람 수. 이 값 하나만 바꾸면 화면 문구까지 모두 바뀐다.
const kFreePeopleLimit = 50;

/// 무료 버전 한도. 이미 입력한 기록의 보기·수정·삭제는 절대 막지 않는다.
class FreeLimits {
  static const people = kFreePeopleLimit;
  static const myEvents = 1;
}
