import { redirect } from "next/navigation";

export default function ClipFeedbackPage() {
  redirect("/content/issues?subject=clip");
}
