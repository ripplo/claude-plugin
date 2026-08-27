# Ripplo for Claude Code

Ripplo reviews your pull requests by driving the app end to end in a real browser and reporting what broke, with the evidence. Ripplo writes and owns the tests — your repository holds none. This plugin connects an app to Ripplo and lets Claude Code fix what a review found.

## Install

```sh
claude plugin marketplace add ripplo/claude-plugin
claude plugin install ripplo
npx ripplo login
```

## Set up

In the app you want reviewed:

```
/ripplo:setup
```

Claude reads the app, installs `@ripplo/auth`, writes the sign-in handler for its auth library, mounts it behind a flag, and verifies the endpoint. You supply the signing secret from the project's Security settings.

## Use

Copy the review id from the Ripplo dashboard, then:

```
/ripplo:review <codeReviewId>
```

Claude pulls the published issues, renders the failing frames, classifies each issue, and fixes the app in your working tree. Push, and Ripplo reviews again.

## Source

This folder is cut from [`ripploai/ripplo`](https://github.com/ripploai/ripplo) on release.
