import nonebot
from nonebot.adapters.qq import Adapter as QQAdapter


def main():
    nonebot.init()

    driver = nonebot.get_driver()
    driver.register_adapter(QQAdapter)

    nonebot.load_from_toml("pyproject.toml")

    nonebot.run()


if __name__ == "__main__":
    main()
