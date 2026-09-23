# Ripplo for Claude Code

Ripplo reviews your pull requests by driving the app end to end in a real browser and reporting what broke, with the evidence. Ripplo writes and owns the tests. The Ripplo plugin lets Claude Code read a review's findings and fix them in your code, and add what a review could not cover.

## Install

```sh
claude plugin marketplace add ripplo/claude-plugin
claude plugin install ripplo@ripplo
npx ripplo login
```

## Set up

In the app you want reviewed:

```sh
npx ripplo setup
```

It connects the repository to Ripplo, creates an OpenID Connect connection, and shows the values to register in your app. Add the sign in with Ripplo connection to your auth library, set the variables on your dev server, deploy, then run `npx ripplo setup --check` to test authentication. When the test passes it installs this plugin in Claude Code and offers to open your project in Ripplo.

## Use

Copy the review id from the Ripplo dashboard, then:

```
/ripplo:review <codeReviewId>
```

Claude pulls the published issues, renders the failing frames, classifies each issue, and fixes the app in your working tree. Push, and Ripplo reviews again.

When a review lists workflows Ripplo could not cover, the app lacks a way for Ripplo to create or observe some state. Copy the command from that list, or from the coverage page:

```
/ripplo:cover <codeReviewId>
```

Claude reads each gap and adds the API or route the app is missing, guarded for Ripplo runs. Push, and the next review covers the workflow.

## Source

This folder is copied from [`ripploai/ripplo`](https://github.com/ripploai/ripplo) on release.
